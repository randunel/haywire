port module Main exposing (main)

import Browser
import Cmd.Extra
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Svg exposing (Svg)
import Svg.Attributes as SvgAttrs
import Svg.Events as SvgEvents
import Animation
import Animation.Messenger
import Json.Encode
import Json.Decode
import Json.Decode.Pipeline as JDPipeline
import PortFunnel.WebSocket as WebSocket exposing (Response(..))
import PortFunnels exposing (FunnelDict, Handler(..), State)


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


getCmdPort : String -> Model -> (Json.Encode.Value -> Cmd Msg)
getCmdPort moduleName model =
    PortFunnels.getCmdPort Process moduleName False


cmdPort : Json.Encode.Value -> Cmd Msg
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
    { send = "sent from frontend (elm)"
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
    |> Cmd.Extra.withNoCmd


type alias Entity =
    { type_ : String
    , id : String
    , clientId : ClientId
    , position : Coordinates
    }


type alias Bullet =
    { coordinates : Coordinates
    , id : BulletId
    , style : Animation.Messenger.State Msg
    }

type alias Player =
    { clientId : ClientId
    , coordinates : PlayerCoordinates
    , team : Team
    , aliveState : AliveState
    }

type AliveState = Alive
    | Dead
    | UnknownAliveState

type alias PlayerCoordinates =
    { clientId : ClientId
    , position : Coordinates
    , orientation : Angles
    , team : String
    }

type Team = UnknownTeam
    | CTTeam
    | TTeam

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

type alias BulletId =
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
    | Process Json.Encode.Value
    | Animate Animation.Msg
    | AnimationEnded BulletId


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateSend newsend ->
            { model | send = newsend } |> Cmd.Extra.withNoCmd

        UpdateUrl url ->
            { model | url = url } |> Cmd.Extra.withNoCmd

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
                |> Cmd.Extra.withNoCmd

        Connect ->
            { model
                | log =
                    ("Connecting to " ++ model.url) :: model.log
            }
                |> Cmd.Extra.withCmd
                    (WebSocket.makeOpenWithKey model.key model.url
                        |> send model
                    )

        Send ->
            { model
                | log =
                    ("Sending \"" ++ model.send ++ "\"") :: model.log
            }
                |> Cmd.Extra.withCmd
                    (WebSocket.makeSend model.key model.send
                        |> send model
                    )

        Close ->
            { model
                | log = "Closing" :: model.log
            }
                |> Cmd.Extra.withCmd
                    (WebSocket.makeClose model.key
                        |> send model
                    )

        Process value ->
            case
                PortFunnels.processValue funnelDict value model.state model
            of
                Err error ->
                    { model | error = Just error } |> Cmd.Extra.withNoCmd

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

        AnimationEnded bulletId ->
            { model
                | bullets = Dict.remove bulletId model.bullets
            }
                |> Cmd.Extra.withNoCmd


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
        Ok command -> handleCommand command message model
        Err err -> appendLog ("Received unexpected " ++ message) model


commandDecoder : Json.Decode.Decoder String
commandDecoder =
    Json.Decode.field "command" Json.Decode.string


handleCommand : String -> String -> Model -> Model
handleCommand command message model =
    case commandFromString command of

        Bullet_impact -> case decodeOriginatorImpact message of
            Just ( playerCoordinates, coordinates ) ->
                model
                    |> handleBulletImpact (getBullet coordinates)
                    |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        Buytime_ended -> model

        Cs_pre_restart -> model

        Decoy_detonate -> case decodeOriginatorEntity message of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Decoy_firing -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Decoy_started -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Flashbang_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Grenade_bounce -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Hegrenade_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Molotov_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Player_activate -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
            Nothing -> appendLog message model

        Player_blind -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        Player_death -> case (decodeVictimAttacker message) of
            Just (victim, attacker) ->
                let
                    updatedModel = handlePlayer victim Dead model
                in
                    handlePlayer attacker UnknownAliveState updatedModel
            Nothing -> appendLog message model

        Player_footstep -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        Player_hurt -> case (decodeVictimAttacker message) of
            Just (victim, attacker) ->
                let
                    updatedModel = handlePlayer victim Alive model
                in
                    handlePlayer attacker UnknownAliveState updatedModel
            Nothing -> appendLog message model

        Player_jump -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        Player_spawn -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        Round_freeze_end -> { model | bullets = Dict.empty }

        Smokegrenade_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Smokegrenade_expired -> case (decodeOriginatorEntity message) of
            Just ( playerCoordinates, entity ) ->
                model
                |> handlePlayer playerCoordinates UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Weapon_reload -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        Weapon_zoom -> case (decodeOriginator message) of
            Just playerCoordinates ->
                model
                |> handlePlayer playerCoordinates Alive
            Nothing -> appendLog message model

        _ -> appendLog message model


handlePlayer : PlayerCoordinates -> AliveState -> Model -> Model
handlePlayer playerCoordinates aliveState model =
    let
        updatedModel = updateCanvasSize playerCoordinates.position model
    in
        { updatedModel | players =
            updatedModel.players
            |> Dict.insert playerCoordinates.clientId (
                ( Dict.get playerCoordinates.clientId updatedModel.players
                |> determineAliveState aliveState
                |> playerFromPlayerCoordinates playerCoordinates
                ) (Dict.get playerCoordinates.clientId updatedModel.players)
            )
        }


handleEntity : Entity -> Model -> Model
handleEntity entity model =
    model


handleBulletImpact : Bullet -> Model -> Model
handleBulletImpact bullet model =
    let
        updatedModel = updateCanvasSize bullet.coordinates model
    in
    { updatedModel | bullets =
        Dict.insert bullet.id bullet updatedModel.bullets
    }


getBulletId : Coordinates -> BulletId
getBulletId coordinates =
    "bullet-" ++ coordinates.x ++ "-" ++ coordinates.y ++ "-" ++ coordinates.z


getBullet : Coordinates -> Bullet
getBullet coordinates =
    let
        bulletId = getBulletId coordinates
    in
        getBulletAnimation bulletId
        |> Bullet coordinates bulletId


getBulletAnimation : BulletId -> Animation.Messenger.State Msg
getBulletAnimation bulletId =
    Animation.queue
    [ Animation.toWith
        ( Animation.easing { duration = 4000, ease = (\x -> x ^ 2) })
        [ Animation.opacity 0 ]
    , Animation.Messenger.send
        ( AnimationEnded bulletId )
    ] ( Animation.style [ Animation.opacity 1.0 ])


updateBulletAnimation : Animation.Msg -> Bullet -> (Bullet, Cmd Msg)
updateBulletAnimation animationMsg bullet =
    let
        (style, cmd) =
            Animation.Messenger.update animationMsg bullet.style
    in
        ({ bullet | style = style }, cmd)


updateCanvasSize : Coordinates -> Model -> Model
updateCanvasSize coordinates model =
    { model | minX =
        String.toFloat coordinates.x
        |> Maybe.withDefault model.minX
        |> min model.minX
    , minY =
        String.toFloat coordinates.y
        |> Maybe.withDefault model.minY
        |> min model.minY
    , maxX =
        String.toFloat coordinates.x
        |> Maybe.withDefault model.maxX
        |> max model.maxX
    , maxY =
        String.toFloat coordinates.y
        |> Maybe.withDefault model.maxY
        |> max model.maxY
    }


decodeOriginatorEntity : String -> Maybe ( PlayerCoordinates, Entity )
decodeOriginatorEntity message =
    case
        ( originatorTeamDecoder [ "originator" ]
        |> Json.Decode.decodeString
        ) message
    of
        Ok playerCoordinates ->
            case
                ( "originator"
                |> entityDecoder
                |> Json.Decode.decodeString
                ) message
            of
                Ok entity -> Just ( playerCoordinates, entity )
                Err err -> Nothing
        Err err -> Nothing


decodeOriginatorImpact : String -> Maybe ( PlayerCoordinates, Coordinates )
decodeOriginatorImpact message =
    case
        ( originatorTeamDecoder [ "originator" ]
        |> Json.Decode.decodeString
        ) message
    of
        Ok playerCoordinates ->
            case
                ( coordinatesDecoder [ "impact", "position" ]
                |> Json.Decode.decodeString
                ) message
            of
                Ok coordinates -> Just ( playerCoordinates, coordinates )
                Err err -> Nothing
        Err err -> Nothing


decodeVictimAttacker : String -> Maybe (PlayerCoordinates, PlayerCoordinates)
decodeVictimAttacker message =
    case
        ( originatorTeamDecoder [ "victim" ]
        |> Json.Decode.decodeString
        ) message
    of
        Ok victim ->
            case
                ( originatorTeamDecoder [ "attacker" ]
                |> Json.Decode.decodeString
                ) message
            of
                Ok attacker -> Just (victim, attacker)
                Err err -> Nothing
        Err err -> Nothing


decodeOriginator : String -> Maybe PlayerCoordinates
decodeOriginator message =
    case Json.Decode.decodeString (originatorTeamDecoder [ "originator" ]) message of
        Ok res -> Just res
        Err err -> Nothing


originatorTeamDecoder : List String -> Json.Decode.Decoder PlayerCoordinates
originatorTeamDecoder nestingKeys =
    Json.Decode.succeed PlayerCoordinates
    |> JDPipeline.requiredAt (nestingKeys ++ [ "clientId" ]) Json.Decode.string
    |> JDPipeline.requiredAt (nestingKeys ++ [ "position" ])(coordinatesDecoder [])
    |> JDPipeline.requiredAt (nestingKeys ++ [ "orientation" ]) anglesDecoder
    |> JDPipeline.optionalAt (nestingKeys ++ [ "team" ]) Json.Decode.string "undefined-team"


entityDecoder : String -> Json.Decode.Decoder Entity
entityDecoder key =
    Json.Decode.succeed Entity
    |> JDPipeline.requiredAt [ "entity", "type" ] Json.Decode.string
    |> JDPipeline.requiredAt [ "entity", "id" ] Json.Decode.string
    |> JDPipeline.requiredAt [ key, "clientId" ] Json.Decode.string
    |> JDPipeline.requiredAt [ "entity", "position" ] ( coordinatesDecoder [])


coordinatesDecoder : List String -> Json.Decode.Decoder Coordinates
coordinatesDecoder nestingKeys =
    Json.Decode.succeed Coordinates
    |> JDPipeline.requiredAt (nestingKeys ++ [ "x" ]) Json.Decode.string
    |> JDPipeline.requiredAt (nestingKeys ++ [ "y" ]) Json.Decode.string
    |> JDPipeline.requiredAt (nestingKeys ++ [ "z" ]) Json.Decode.string


anglesDecoder : Json.Decode.Decoder Angles
anglesDecoder =
    Json.Decode.succeed Angles
    |> JDPipeline.required "ang0" Json.Decode.string
    |> JDPipeline.required "ang1" Json.Decode.string
    |> JDPipeline.required "ang2" Json.Decode.string


determineAliveState : AliveState -> Maybe Player -> AliveState
determineAliveState aliveState maybePlayer =
    case aliveState of
        UnknownAliveState ->
            case maybePlayer of
                Just player -> player.aliveState
                _ -> aliveState
        _ -> aliveState


playerFromPlayerCoordinates : PlayerCoordinates -> AliveState -> Maybe Player -> Player
playerFromPlayerCoordinates playerCoordinates aliveState maybePlayer =
    let ( oldTeam, oldAliveState ) =
        case maybePlayer of
            Just player -> ( player.team, player.aliveState )
            _ -> ( UnknownTeam, UnknownAliveState )
    in
        ( case aliveState of
            UnknownAliveState -> oldAliveState
            _ -> aliveState
        )
        |> Player playerCoordinates.clientId playerCoordinates (
            case playerCoordinates.team of
                "3" -> CTTeam
                "2" -> TTeam
                "undefined-team" -> oldTeam
                _ -> oldTeam
            )


commandFromString : String -> Command
commandFromString str =
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
                |> Cmd.Extra.withNoCmd

        WebSocket.ConnectedResponse r ->
            { model | log = ("Connected: " ++ r.description) :: model.log }
                |> Cmd.Extra.withNoCmd

        WebSocket.ClosedResponse { code, wasClean, expected } ->
            { model
                | log =
                    ("Closed, " ++ closedString code wasClean expected)
                        :: model.log
            }
                |> Cmd.Extra.withNoCmd

        WebSocket.ErrorResponse error ->
            { model | log = WebSocket.errorToString error :: model.log }
                |> Cmd.Extra.withNoCmd

        _ ->
            case WebSocket.reconnectedResponses response of
                [] ->
                    model |> Cmd.Extra.withNoCmd

                [ ReconnectedResponse r ] ->
                    { model | log = ("Reconnected: " ++ r.description) :: model.log }
                        |> Cmd.Extra.withNoCmd

                list ->
                    { model | log = ("list") :: model.log }
                        |> Cmd.Extra.withNoCmd


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
    Html.b [] [ Html.text string ]


br : Html msg
br =
    Html.br [] []


docp : String -> Html Msg
docp string =
    Html.p [] [ Html.text string ]


view : Model -> Html Msg
view model =
    let
        isConnected =
            WebSocket.isConnected model.key model.state.websocket
    in
    Html.div
        [ Html.Attributes.style "width" "90%"
        , Html.Attributes.style "margin" "auto"
        , Html.Attributes.style "margin-top" "1em"
        , Html.Attributes.style "padding" "1em"
        , Html.Attributes.style "border" "solid"
        ]
        [ Html.h1 [] [ Html.text "Haywire sample" ]
        , Html.p []
            [ Html.input
                [ Html.Attributes.value model.send
                , Html.Events.onInput UpdateSend
                , Html.Attributes.size 50
                ]
                []
            , Html.text " "
            , Html.button
                [ Html.Events.onClick Send
                , Html.Attributes.disabled (not isConnected)
                ]
                [ Html.text "Send" ]
            ]
        , Html.p []
            [ b "url: "
            , Html.input
                [ Html.Attributes.value model.url
                , Html.Events.onInput UpdateUrl
                , Html.Attributes.size 30
                , Html.Attributes.disabled isConnected
                ]
                []
            , Html.text " "
            , if isConnected then
                Html.button [ Html.Events.onClick Close ]
                    [ Html.text "Close" ]

              else
                Html.button [ Html.Events.onClick Connect ]
                    [ Html.text "Connect" ]
            , br
            , b "auto reopen: "
            , Html.input
                [ Html.Attributes.type_ "checkbox"
                , Html.Events.onClick ToggleAutoReopen
                , Html.Attributes.checked <|
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
        , Html.p [] <|
            List.concat
                [ [ b "Players:"
                  , br
                  ]
                , List.intersperse br (List.map Html.text (List.map (\p -> "clientId:" ++ p.clientId ++ " x:" ++ p.coordinates.position.x ++ " y:" ++ p.coordinates.position.y ++ " z:" ++ p.coordinates.position.z) (Dict.values model.players)))
                -- , [ br, b "Bullets:", br ]
                -- , List.intersperse br (List.map Html.text (List.map (\bullet -> "id:" ++ (bullet.id) ++ " x:" ++ bullet.coordinates.x ++ " y:" ++ bullet.coordinates.y ++ " z:" ++ bullet.coordinates.z) (Dict.values model.bullets)))
                ]
        , Html.p [] <|
            List.concat
                [ [ b "Log:"
                  , br
                  ]
                , List.intersperse br (List.map Html.text model.log)
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

playerSvg model player =
    let
        cx = (((Maybe.withDefault 0 (String.toFloat player.coordinates.position.x)) - model.minX) * 800 / (model.maxX - model.minX))
        cy = (((Maybe.withDefault 0 (String.toFloat player.coordinates.position.y)) - model.minY) * 800 / (model.maxY - model.minY))
        r =
            case player.aliveState of
                Alive -> 5.0
                Dead -> 2.0
                UnknownAliveState -> 5.0
        yaw = (Maybe.withDefault 0 (String.toFloat player.coordinates.orientation.ang1) - 135)
    in
        Svg.g
        [ SvgAttrs.transform ("rotate(" ++ String.fromFloat yaw ++ ", " ++ String.fromFloat cx ++ ", " ++ String.fromFloat cy ++ ")") ]
        [ Svg.path
            [ SvgAttrs.d <| "M" ++ (String.fromFloat (cx - r)) ++ " " ++ (String.fromFloat cy)
                ++ " A " ++ (String.fromFloat r) ++ " " ++ (String.fromFloat r) ++ ", 0, 1, 1, " ++ (String.fromFloat cx) ++ " " ++ (String.fromFloat (cy + r))
                ++ " L " ++ (String.fromFloat cx) ++ " " ++ (String.fromFloat (cy)) ++ " Z"
            , SvgAttrs.fill (case player.team of
                UnknownTeam -> "orange"
                CTTeam -> "blue"
                TTeam -> "red"
                )
            ]
            []
        , Svg.path
            [ SvgAttrs.d <| "M" ++ (String.fromFloat (cx - r)) ++ " " ++ (String.fromFloat cy)
                ++ " A " ++ (String.fromFloat r) ++ " " ++ (String.fromFloat r) ++ ", 0, 0, 0, " ++ (String.fromFloat cx) ++ " " ++ (String.fromFloat (cy + r))
                ++ " L " ++ (String.fromFloat cx) ++ " " ++ (String.fromFloat (cy)) ++ " Z"
            , SvgAttrs.fill "aqua"
            ]
            []
        ]
