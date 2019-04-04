port module Main exposing (main)

{-| WebSocketClient Example
-}

import Browser
import Cmd.Extra exposing (addCmd, addCmds, withCmd, withCmds, withNoCmd)
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, h1, input, p, span, text)
import Html.Attributes exposing (checked, disabled, href, size, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Svg exposing (Svg)
import Svg.Attributes as SvgAttrs
import Svg.Events as SvgEvents
import Animation
import Animation.Messenger
import Json.Encode exposing (Value)
import Json.Decode exposing (Decoder, field, string, float, at)
import PortFunnel.WebSocket as WebSocket exposing (Response(..))
import PortFunnels exposing (FunnelDict, Handler(..), State)



{- This section contains boilerplate that you'll always need.

   First, copy PortFunnels.elm into your project, and modify it
   to support all the funnel modules you use.

   Then update the `handlers` list with an entry for each funnel.

   Those handler functions are the meat of your interaction with each
   funnel module.
-}


handlers : List (Handler Model Msg)
handlers =
    [ WebSocketHandler socketHandler
    ]


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ PortFunnels.subscriptions Process model
        , Animation.subscription Animate (List.map (\bullet -> bullet.style) (Dict.values model.bullets))
        ]


funnelDict : FunnelDict Model Msg
funnelDict =
    PortFunnels.makeFunnelDict handlers getCmdPort


{-| Get a possibly simulated output port.
-}
getCmdPort : String -> Model -> (Value -> Cmd Msg)
getCmdPort moduleName model =
    PortFunnels.getCmdPort Process moduleName False


{-| The real output port.
-}
cmdPort : Value -> Cmd Msg
cmdPort =
    PortFunnels.getCmdPort Process "" False



-- MODEL


defaultUrl : String
defaultUrl =
    "ws://localhost:3000"


type alias Model =
    { send : String
    , log : List String
    , url : String
    , wasLoaded : Bool
    , state : State
    , key : String
    , error : Maybe String
    , players : Dict.Dict String Player
    , entities : Dict.Dict String Entity
    , bullets : Dict.Dict String Bullet
    , minX : Float
    , minY : Float
    , maxX : Float
    , maxY : Float
    }


main =
    Browser.element
    { init = init
    , update = update
    , view = view
    , subscriptions = subscriptions
    }


init : () -> ( Model, Cmd Msg )
init _ =
    { send = "Hello World!"
    , log = []
    , url = defaultUrl
    , wasLoaded = False
    , state = PortFunnels.initialState
    , key = "socket"
    , error = Nothing
    , players = Dict.empty
    , entities = Dict.empty
    , bullets = Dict.empty
    , minX = 0
    , minY = 0
    , maxX = 0
    , maxY = 0
    }
    |> withNoCmd

type alias Bullet =
    { coordinates : Coordinates
    , id : String
    , style : Animation.Messenger.State Msg
    }

type alias Entity =
    { clientId : ClientId
    , coordinates : PlayerCoordinates
    }

type alias Player =
    { clientId : ClientId
    , coordinates : PlayerCoordinates
    , aliveState : AliveState
    }

type AliveState = Alive
    | Dead
    | Unknown

type alias Position =
    { position : Coordinates }

type alias PlayerCoordinates =
    { clientId : ClientId
    , position : Coordinates
    , orientation : Angles
    }

type Command =
    Bullet_impact
    | Buytime_ended
    | Cs_pre_restart
    | Decoy_detonate
    | Decoy_firing
    | Decoy_started
    | Flashbang_detonate
    | Grenade_bounce
    | Hegrenade_bounce
    | Hegrenade_detonate
    | Molotov_detonate
    | Player_activate
    | Player_blind
    | Player_death
    | Player_footstep
    | Player_hurt
    | Player_jump
    | Player_spawn
    | Round_freeze_end
    | Smokegrenade_detonate
    | Smokegrenade_expired
    | Weapon_reload
    | Weapon_zoom
    | Unknown_command

type alias ClientId =
    String

type alias Coordinates =
    { x : String
    , y : String
    , z : String
    }

type alias Angles =
    { ang0 : String
    , ang1 : String
    , ang2 : String
    }


-- UPDATE


type Msg =
    UpdateSend String
    | UpdateUrl String
    | ToggleAutoReopen
    | Connect
    | Close
    | Send
    | Process Value
    | Animate Animation.Msg
    | AnimationEnded Position


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend newsend ->
            { model | send = newsend } |> withNoCmd

        UpdateUrl url ->
            { model | url = url } |> withNoCmd

        ToggleAutoReopen ->
            let
                state =
                    model.state

                socketState =
                    state.websocket

                autoReopen =
                    WebSocket.willAutoReopen model.key socketState
            in
            { model
                | state =
                    { state
                        | websocket =
                            WebSocket.setAutoReopen
                                model.key
                                (not autoReopen)
                                socketState
                    }
            }
                |> withNoCmd

        Connect ->
            { model
                | log =
                    ("Connecting to " ++ model.url) :: model.log
            }
                |> withCmd
                    (WebSocket.makeOpenWithKey model.key model.url
                        |> send model
                    )

        Send ->
            { model
                | log =
                    ("Sending \"" ++ model.send ++ "\"") :: model.log
            }
                |> withCmd
                    (WebSocket.makeSend model.key model.send
                        |> send model
                    )

        Close ->
            { model
                | log = "Closing" :: model.log
            }
                |> withCmd
                    (WebSocket.makeClose model.key
                        |> send model
                    )

        Process value ->
            case
                PortFunnels.processValue funnelDict value model.state model
            of
                Err error ->
                    { model | error = Just error } |> withNoCmd

                Ok res ->
                    res

        Animate animationMsg ->
            let
                bulletCmds =
                    List.map (updateBulletAnimation animationMsg) (Dict.values model.bullets)
                (bulletsList, cmds) =
                    List.unzip bulletCmds
            in
                ({ model | bullets = Dict.fromList (List.map (\bullet -> (bullet.id, bullet)) bulletsList) }, Cmd.batch cmds)

        AnimationEnded position ->
            { model
                | bullets = Dict.remove (getBulletId position.position) model.bullets
                -- , log = ("Removed " ++ (getBulletId position.position)) :: model.log
            }
                |> withNoCmd


updateBulletAnimation : Animation.Msg -> Bullet -> (Bullet, Cmd Msg)
updateBulletAnimation animationMsg bullet =
    let
        (style, cmd) =
            Animation.Messenger.update animationMsg bullet.style
    in
        ({ bullet | style = style }, cmd)

send : Model -> WebSocket.Message -> Cmd Msg
send model message =
    WebSocket.send (getCmdPort WebSocket.moduleName model) message


doIsLoaded : Model -> Model
doIsLoaded model =
    if not model.wasLoaded && WebSocket.isLoaded model.state.websocket then
        { model
        | wasLoaded = True
        }

    else
        model

appendLog : String -> Model -> Model
appendLog str model =
    { model | log = str :: model.log }

handleMessage : Model -> String -> Model
handleMessage model message =
    case Json.Decode.decodeString commandDecoder message of
        Ok res -> handleCommand res message model
        Err err -> appendLog ("Received unexpected " ++ message) model

commandDecoder : Decoder String
commandDecoder =
    field "command" string

getBulletId : Coordinates -> String
getBulletId coordinates =
    "bullet-" ++ coordinates.x ++ "-" ++ coordinates.y ++ "-" ++ coordinates.z

handleCommand : String -> String -> Model -> Model
handleCommand command message model =
    case stringToCommand command of
        Bullet_impact -> case (decodeOriginatorImpact message) of
            Just (playerCoords, position) -> handlePlayerCoordinates (
                handleBulletImpact model (Bullet position.position (getBulletId position.position) (
                    Animation.interrupt [Animation.toWith (Animation.easing {duration = 4000, ease = (\x -> x ^ 2)}) [Animation.opacity 0], Animation.Messenger.send (AnimationEnded position)] (Animation.style [Animation.opacity 1.0])
                    ))
                ) playerCoords Alive
            Nothing -> appendLog message model
        Buytime_ended -> model
        Cs_pre_restart -> model
        Decoy_detonate -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Decoy_firing -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Decoy_started -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Flashbang_detonate -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Grenade_bounce -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Hegrenade_detonate -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Molotov_detonate -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Player_activate -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Player_blind -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Alive
            Nothing -> appendLog message model
        Player_death -> case (decodeVictimAttacker message) of
            Just (victim, attacker) -> handlePlayerCoordinates (handlePlayerCoordinates model victim Dead) attacker Alive
            Nothing -> appendLog message model
        Player_footstep -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Alive
            Nothing -> appendLog message model
        Player_hurt -> case (decodeVictimAttacker message) of
            Just (victim, attacker) -> handlePlayerCoordinates (handlePlayerCoordinates model victim Alive) attacker Alive
            Nothing -> appendLog message model
        Player_jump -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Alive
            Nothing -> appendLog message model
        Player_spawn -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Alive
            Nothing -> appendLog message model
        Round_freeze_end -> { model | bullets = Dict.empty }
        Smokegrenade_detonate -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Smokegrenade_expired -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Unknown
            Nothing -> appendLog message model
        Weapon_reload -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Alive
            Nothing -> appendLog message model
        Weapon_zoom -> case (decodeOriginator message) of
            Just playerCoords -> handlePlayerCoordinates model playerCoords Alive
            Nothing -> appendLog message model
        _ -> appendLog message model

handleBulletImpact : Model -> Bullet -> Model
handleBulletImpact model bullet =
    {
        model | bullets = Dict.insert bullet.id bullet model.bullets
        , minX = min model.minX (Maybe.withDefault model.minX (String.toFloat bullet.coordinates.x))
        , minY = min model.minY (Maybe.withDefault model.minY (String.toFloat bullet.coordinates.y))
        , maxX = max model.maxX (Maybe.withDefault model.maxX (String.toFloat bullet.coordinates.x))
        , maxY = max model.maxY (Maybe.withDefault model.maxY (String.toFloat bullet.coordinates.y))
    }

handlePlayerCoordinates : Model -> PlayerCoordinates -> AliveState -> Model
handlePlayerCoordinates model playerCoords aliveState =
    {
        model | players =
            Dict.insert playerCoords.clientId (Player playerCoords.clientId playerCoords (
                case aliveState of
                    Unknown ->
                        case Dict.get playerCoords.clientId model.players of
                            Just p -> p.aliveState
                            _ -> aliveState
                    _ -> aliveState
            )) model.players
        , minX = min model.minX (Maybe.withDefault model.minX (String.toFloat playerCoords.position.x))
        , minY = min model.minY (Maybe.withDefault model.minY (String.toFloat playerCoords.position.y))
        , maxX = max model.maxX (Maybe.withDefault model.maxX (String.toFloat playerCoords.position.x))
        , maxY = max model.maxY (Maybe.withDefault model.maxY (String.toFloat playerCoords.position.y))
    }

decodeVictimAttacker : String -> Maybe (PlayerCoordinates, PlayerCoordinates)
decodeVictimAttacker message =
    case Json.Decode.decodeString victimDecoder message of
        Ok victim -> case Json.Decode.decodeString attackerDecoder message of
            Ok attacker -> Just (victim, attacker)
            Err err -> Nothing
        Err err -> Nothing

victimDecoder : Decoder PlayerCoordinates
victimDecoder =
    ( Json.Decode.map3 PlayerCoordinates
        ( at [ "victim", "clientId" ] clientIdDecoder )
        ( at [ "victim", "position" ] coordinatesDecoder )
        ( at [ "victim", "orientation" ] anglesDecoder )
    )

attackerDecoder : Decoder PlayerCoordinates
attackerDecoder =
    ( Json.Decode.map3 PlayerCoordinates
        ( at [ "attacker", "clientId" ] clientIdDecoder )
        ( at [ "attacker", "position" ] coordinatesDecoder )
        ( at [ "attacker", "orientation" ] anglesDecoder )
    )

decodeOriginatorImpact : String -> Maybe (PlayerCoordinates, Position)
decodeOriginatorImpact message =
    case Json.Decode.decodeString originatorDecoder message of
        Ok originator -> case Json.Decode.decodeString positionDecoder message of
            Ok position -> Just (originator, position)
            Err err -> Nothing
        Err err -> Nothing

decodeOriginator : String -> Maybe PlayerCoordinates
decodeOriginator message =
    case Json.Decode.decodeString originatorDecoder message of
        Ok res -> Just res
        Err err -> Nothing

positionDecoder : Decoder Position
positionDecoder =
    ( Json.Decode.map Position
        ( at [ "originator", "position" ] coordinatesDecoder )
    )

originatorDecoder : Decoder PlayerCoordinates
originatorDecoder =
    ( Json.Decode.map3 PlayerCoordinates
        ( at [ "originator", "clientId" ] clientIdDecoder )
        ( at [ "originator", "position" ] coordinatesDecoder )
        ( at [ "originator", "orientation" ] anglesDecoder )
    )

clientIdDecoder : Decoder ClientId
clientIdDecoder =
    string

coordinatesDecoder : Decoder Coordinates
coordinatesDecoder =
    ( Json.Decode.map3 Coordinates
        ( field "x" string )
        ( field "y" string )
        ( field "z" string )
    )

anglesDecoder : Decoder Angles
anglesDecoder =
    ( Json.Decode.map3 Angles
        ( field "ang0" string )
        ( field "ang1" string )
        ( field "ang2" string )
    )

stringToCommand : String -> Command
stringToCommand str =
    case str of
        "bullet_impact" -> Bullet_impact
        "buytime_ended" -> Buytime_ended
        "cs_pre_restart" -> Cs_pre_restart
        "decoy_detonate" -> Decoy_detonate
        "decoy_firing" -> Decoy_firing
        "decoy_started" -> Decoy_started
        "flashbang_detonate" -> Flashbang_detonate
        "grenade_bounce" -> Grenade_bounce
        "hegrenade_bounce" -> Hegrenade_bounce
        "hegrenade_detonate" -> Hegrenade_detonate
        "molotov_detonate" -> Molotov_detonate
        "player_activate" -> Player_activate
        "player_blind" -> Player_blind
        "player_death" -> Player_death
        "player_footstep" -> Player_footstep
        "player_hurt" -> Player_hurt
        "player_jump" -> Player_jump
        "player_spawn" -> Player_spawn
        "round_freeze_end" -> Round_freeze_end
        "smokegrenade_detonate" -> Smokegrenade_detonate
        "smokegrenade_expired" -> Smokegrenade_expired
        "weapon_reload" -> Weapon_reload
        "weapon_zoom" -> Weapon_zoom
        _ -> Unknown_command

socketHandler : Response -> State -> Model -> ( Model, Cmd Msg )
socketHandler response state mdl =
    let
        model =
            doIsLoaded
                { mdl
                    | state = state
                    , error = Nothing
                }
    in
    case response of
        WebSocket.MessageReceivedResponse { message } ->
            handleMessage model message
                |> withNoCmd

        WebSocket.ConnectedResponse r ->
            { model | log = ("Connected: " ++ r.description) :: model.log }
                |> withNoCmd

        WebSocket.ClosedResponse { code, wasClean, expected } ->
            { model
                | log =
                    ("Closed, " ++ closedString code wasClean expected)
                        :: model.log
            }
                |> withNoCmd

        WebSocket.ErrorResponse error ->
            { model | log = WebSocket.errorToString error :: model.log }
                |> withNoCmd

        _ ->
            case WebSocket.reconnectedResponses response of
                [] ->
                    model |> withNoCmd

                [ ReconnectedResponse r ] ->
                    { model | log = ("Reconnected: " ++ r.description) :: model.log }
                        |> withNoCmd

                list ->
                    { model | log = ("list") :: model.log }
                        |> withNoCmd


closedString : WebSocket.ClosedCode -> Bool -> Bool -> String
closedString code wasClean expected =
    "code: "
        ++ WebSocket.closedCodeToString code
        ++ ", "
        ++ (if wasClean then
                "clean"

            else
                "not clean"
           )
        ++ ", "
        ++ (if expected then
                "expected"

            else
                "NOT expected"
           )



-- VIEW


b : String -> Html Msg
b string =
    Html.b [] [ text string ]


br : Html msg
br =
    Html.br [] []


docp : String -> Html Msg
docp string =
    p [] [ text string ]


view : Model -> Html Msg
view model =
    let
        isConnected =
            WebSocket.isConnected model.key model.state.websocket
    in
    div
        [ style "width" "90%"
        , style "margin" "auto"
        , style "margin-top" "1em"
        , style "padding" "1em"
        , style "border" "solid"
        ]
        [ h1 [] [ text "Haywire sample" ]
        , p []
            [ input
                [ value model.send
                , onInput UpdateSend
                , size 50
                ]
                []
            , text " "
            , button
                [ onClick Send
                , disabled (not isConnected)
                ]
                [ text "Send" ]
            ]
        , p []
            [ b "url: "
            , input
                [ value model.url
                , onInput UpdateUrl
                , size 30
                , disabled isConnected
                ]
                []
            , text " "
            , if isConnected then
                button [ onClick Close ]
                    [ text "Close" ]

              else
                button [ onClick Connect ]
                    [ text "Connect" ]
            , br
            , b "auto reopen: "
            , input
                [ type_ "checkbox"
                , onClick ToggleAutoReopen
                , checked <|
                    WebSocket.willAutoReopen
                        model.key
                        model.state.websocket
                ]
                []
            ]
        , Svg.svg
            [ SvgAttrs.width "800"
            , SvgAttrs.height "800"
            ]
            (
                (List.map (playerSvg model) (Dict.values model.players))
                ++
                (List.map (bulletsSvg model) (Dict.values model.bullets))
            )
        , p [] <|
            List.concat
                [ [ b "Players:"
                  , br
                  ]
                , List.intersperse br (List.map text (List.map (\p -> "clientId:" ++ p.clientId ++ " x:" ++ p.coordinates.position.x ++ " y:" ++ p.coordinates.position.y ++ " z:" ++ p.coordinates.position.z) (Dict.values model.players)))
                , [ br, b "Bullets:", br ]
                , List.intersperse br (List.map text (List.map (\bullet -> "id:" ++ (bullet.id) ++ " x:" ++ bullet.coordinates.x ++ " y:" ++ bullet.coordinates.y ++ " z:" ++ bullet.coordinates.z) (Dict.values model.bullets)))
                ]
        , p [] <|
            List.concat
                [ [ b "Log:"
                  , br
                  ]
                , List.intersperse br (List.map text model.log)
                ]
        ]

bulletsSvg model bullet = Svg.circle
    (Animation.render bullet.style
    ++
    [ SvgAttrs.cx <| String.fromFloat (((Maybe.withDefault 0 (String.toFloat bullet.coordinates.x)) - model.minX) * 800 / (model.maxX - model.minX))
    , SvgAttrs.cy <| String.fromFloat (((Maybe.withDefault 0 (String.toFloat bullet.coordinates.y)) - model.minY) * 800 / (model.maxY - model.minY))
    , SvgAttrs.r <| "1"
    , SvgAttrs.fill "black"
    , SvgAttrs.id bullet.id
    ])
    []

playerSvg model player = Svg.circle
    [ SvgAttrs.cx <| String.fromFloat (((Maybe.withDefault 0 (String.toFloat player.coordinates.position.x)) - model.minX) * 800 / (model.maxX - model.minX))
    , SvgAttrs.cy <| String.fromFloat (((Maybe.withDefault 0 (String.toFloat player.coordinates.position.y)) - model.minY) * 800 / (model.maxY - model.minY))
    , SvgAttrs.r <| case player.aliveState of
        Alive -> "5"
        Dead -> "2"
        Unknown -> "5"
    , SvgAttrs.fill "orange"
    , SvgAttrs.stroke "black"
    , SvgAttrs.strokeWidth "2"
    ]
    []
