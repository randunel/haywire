port module Main exposing (main)

import Browser
import Browser.Events
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
        , Browser.Events.onKeyDown (keyPressDecoder KeyDown model)
        , Browser.Events.onKeyUp (keyPressDecoder KeyUp model)
        , Browser.Events.onVisibilityChange VisibilityChanged
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
    , bullets : Dict.Dict BulletId Bullet
    , minX : Float
    , minY : Float
    , maxX : Float
    , maxY : Float
    , bulletsResetCount : Int
    , entitiesResetCount : Int
    , enablePlayerNames : Bool
    , enablePlayerAnimations : Bool
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
    , bulletsResetCount = 200
    , entitiesResetCount = 200
    , enablePlayerNames = False
    , enablePlayerAnimations = True
    }
    |> Cmd.Extra.withNoCmd


type alias Entity =
    { type_ : String
    , id : String
    , clientId : ClientId
    , coordinates : Coordinates
    }


type alias Bullet =
    { coordinates : Coordinates
    , id : BulletId
    , style : Animation.Messenger.State Msg
    }

type alias Player =
    { clientId : ClientId
    , position : Position
    , team : Team
    , aliveState : AliveState
    , name : String
    }

type AliveState = Alive
    | Dead
    | UnknownAliveState

type alias Position =
    { coordinates : Coordinates
    , orientation : Angles
    }

type alias DecodedPlayerDetails =
    { clientId : ClientId
    , coordinates : Coordinates
    , orientation : Angles
    , team : String
    , name : String
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

type KeyPressMotion =
    KeyDown
    | KeyUp

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
    | OnKeyPress KeyPressMotion String
    | VisibilityChanged Browser.Events.Visibility


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

        OnKeyPress keyPressMotion str ->
            handleKeyPress str keyPressMotion model
            |> Cmd.Extra.withNoCmd

        VisibilityChanged visibility ->
            handleVisibilityChanged visibility model
            |> Cmd.Extra.withNoCmd


handleKeyPress : String -> KeyPressMotion -> Model -> Model
handleKeyPress keyName keyPressMotion model =
    case keyName of
        "Control" ->
            case keyPressMotion of
                KeyDown -> { model | enablePlayerNames = True }
                KeyUp -> { model | enablePlayerNames = False }
        _ -> model


handleVisibilityChanged : Browser.Events.Visibility -> Model -> Model
handleVisibilityChanged visibility model =
    case visibility of
        Browser.Events.Visible ->
            { model
                | enablePlayerAnimations = True
            }
        Browser.Events.Hidden ->
            { model
                | enablePlayerNames = False
            , enablePlayerAnimations = False
            }


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
            Just ( playerDetails, coordinates ) ->
                model
                    |> updateCanvasSize playerDetails.coordinates
                    |> updateCanvasSize coordinates
                    |> handleBulletImpact (getBullet coordinates)
                    |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        Buytime_ended -> model

        Cs_pre_restart -> model

        Decoy_detonate -> case decodeOriginatorEntity message of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Decoy_firing -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Decoy_started -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Flashbang_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Grenade_bounce -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Hegrenade_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Molotov_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Player_activate -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails UnknownAliveState
            Nothing -> appendLog message model

        Player_blind -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        Player_death -> case (decodeVictimAttacker message) of
            Just (victim, attacker) ->
                model
                |> updateCanvasSize victim.coordinates
                |> updateCanvasSize attacker.coordinates
                |> handlePlayer victim Dead
                |> handlePlayer attacker UnknownAliveState
            Nothing -> appendLog message model

        Player_footstep -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        Player_hurt -> case (decodeVictimAttacker message) of
            Just (victim, attacker) ->
                model
                |> updateCanvasSize victim.coordinates
                |> updateCanvasSize attacker.coordinates
                |> handlePlayer victim Alive
                |> handlePlayer attacker UnknownAliveState
            Nothing -> appendLog message model

        Player_jump -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        Player_spawn -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        Round_freeze_end -> { model | bullets = Dict.empty }

        Smokegrenade_detonate -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Smokegrenade_expired -> case (decodeOriginatorEntity message) of
            Just ( playerDetails, entity ) ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> updateCanvasSize entity.coordinates
                |> handlePlayer playerDetails UnknownAliveState
                |> handleEntity entity
            Nothing -> appendLog message model

        Weapon_reload -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        Weapon_zoom -> case (decodeOriginator message) of
            Just playerDetails ->
                model
                |> updateCanvasSize playerDetails.coordinates
                |> handlePlayer playerDetails Alive
            Nothing -> appendLog message model

        _ -> appendLog message model


handlePlayer : DecodedPlayerDetails -> AliveState -> Model -> Model
handlePlayer playerDetails aliveState model =
    let
        player =
            findOrCreatePlayer playerDetails.clientId model.players
            |> updatePlayerCoordinates playerDetails
            |> updatePlayerTeam playerDetails.team
            |> updatePlayerAliveState aliveState
            |> updatePlayerName playerDetails.name
    in
    { model | players =
        model.players
        |> Dict.insert playerDetails.clientId player
    }


updatePlayerCoordinates : DecodedPlayerDetails -> Player -> Player
updatePlayerCoordinates playerDetails player =
    { player | position =
        Position playerDetails.coordinates playerDetails.orientation
    }


updatePlayerTeam : String -> Player -> Player
updatePlayerTeam team player =
    { player | team =
        case team of
            "3" -> CTTeam
            "2" -> TTeam
            "undefined-team" -> player.team
            _ -> player.team
    }


updatePlayerName : String -> Player -> Player
updatePlayerName name player =
    { player | name =
        case name of
            "" -> player.name
            _ -> name
    }


updatePlayerAliveState : AliveState -> Player -> Player
updatePlayerAliveState aliveState player =
    { player | aliveState =
        case aliveState of
            UnknownAliveState -> player.aliveState
            _ -> aliveState
    }


findOrCreatePlayer : ClientId -> Dict ClientId Player -> Player
findOrCreatePlayer clientId players =
    case Dict.get clientId players of
        Just player -> player
        _ -> Player
            clientId
            ( Position ( Coordinates "" "" "" ) ( Angles "" "" "" ) )
            UnknownTeam
            UnknownAliveState
            ""


handleEntity : Entity -> Model -> Model
handleEntity entity model =
    model


handleBulletImpact : Bullet -> Model -> Model
handleBulletImpact bullet model =
    if Dict.size model.bullets > model.bulletsResetCount then
        { model | bullets = Dict.empty
        }
    else
        { model | bullets =
            Dict.insert bullet.id bullet model.bullets
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


decodeOriginatorEntity : String -> Maybe ( DecodedPlayerDetails, Entity )
decodeOriginatorEntity message =
    case
        ( originatorTeamDecoder [ "originator" ]
        |> Json.Decode.decodeString
        ) message
    of
        Ok playerDetails ->
            case
                ( "originator"
                |> entityDecoder
                |> Json.Decode.decodeString
                ) message
            of
                Ok entity -> Just ( playerDetails, entity )
                Err err -> Nothing
        Err err -> Nothing


decodeOriginatorImpact : String -> Maybe ( DecodedPlayerDetails, Coordinates )
decodeOriginatorImpact message =
    case
        ( originatorTeamDecoder [ "originator" ]
        |> Json.Decode.decodeString
        ) message
    of
        Ok playerDetails ->
            case
                ( coordinatesDecoder [ "impact", "coordinates" ]
                |> Json.Decode.decodeString
                ) message
            of
                Ok coordinates -> Just ( playerDetails, coordinates )
                Err err -> Nothing
        Err err -> Nothing


decodeVictimAttacker : String -> Maybe (DecodedPlayerDetails, DecodedPlayerDetails)
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


decodeOriginator : String -> Maybe DecodedPlayerDetails
decodeOriginator message =
    case Json.Decode.decodeString (originatorTeamDecoder [ "originator" ]) message of
        Ok res -> Just res
        Err err -> Nothing


originatorTeamDecoder : List String -> Json.Decode.Decoder DecodedPlayerDetails
originatorTeamDecoder nestingKeys =
    Json.Decode.succeed DecodedPlayerDetails
    |> JDPipeline.requiredAt (nestingKeys ++ [ "clientId" ]) Json.Decode.string
    |> JDPipeline.requiredAt (nestingKeys ++ [ "coordinates" ])(coordinatesDecoder [])
    |> JDPipeline.requiredAt (nestingKeys ++ [ "orientation" ]) anglesDecoder
    |> JDPipeline.optionalAt (nestingKeys ++ [ "team" ]) Json.Decode.string "undefined-team"
    |> JDPipeline.optionalAt (nestingKeys ++ [ "name" ]) Json.Decode.string ""


entityDecoder : String -> Json.Decode.Decoder Entity
entityDecoder key =
    Json.Decode.succeed Entity
    |> JDPipeline.requiredAt [ "entity", "type" ] Json.Decode.string
    |> JDPipeline.requiredAt [ "entity", "id" ] Json.Decode.string
    |> JDPipeline.requiredAt [ key, "clientId" ] Json.Decode.string
    |> JDPipeline.requiredAt [ "entity", "coordinates" ] ( coordinatesDecoder [])


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


keyPressDecoder : KeyPressMotion -> Model -> Json.Decode.Decoder Msg
keyPressDecoder keyPressMotion model =
    OnKeyPress keyPressMotion
    |> Json.Decode.succeed
    |> JDPipeline.requiredAt [ "key" ] Json.Decode.string


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
                , List.intersperse br (List.map Html.text (List.map (\p -> "name: " ++ p.name ++ " x:" ++ p.position.coordinates.x ++ " y:" ++ p.position.coordinates.y ++ " z:" ++ p.position.coordinates.z ++ " ang1:" ++ p.position.orientation.ang1) (Dict.values model.players)))
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
    ( Animation.render bullet.style
    ++
    [ SvgAttrs.cx <|
        let x =
                bullet.coordinates.x
                |> String.toFloat
                |> Maybe.withDefault 0
        in
            ( x - model.minX ) * 800 / ( model.maxX - model.minX )
            |> String.fromFloat
    , SvgAttrs.cy <|
        let y =
                bullet.coordinates.y
                |> String.toFloat
                |> Maybe.withDefault 0
        in
            ( y - model.minY ) * 800 / ( model.maxY - model.minY )
            |> String.fromFloat
    , SvgAttrs.r <| "1"
    , SvgAttrs.fill "black"
    ])
    []

playerSvg model player =
    let
        cx =
            ( ( player.position.coordinates.x
            |> String.toFloat
            |> Maybe.withDefault 0
            ) - model.minX ) * 800 / ( model.maxX - model.minX )
        cy =
            ( ( player.position.coordinates.y
            |> String.toFloat
            |> Maybe.withDefault 0
            ) - model.minY ) * 800 / ( model.maxY - model.minY )
        r =
            case player.aliveState of
                Alive -> 5.0
                Dead -> 2.0
                UnknownAliveState -> 5.0
        yaw =
            ( player.position.orientation.ang1
            |> String.toFloat
            |> Maybe.withDefault 0
            ) - 135
    in
        Svg.g
        []
        ( ( if model.enablePlayerNames == True then
            [ Svg.text_
            [ SvgAttrs.x ( String.fromFloat ( cx + 3 ) )
            , SvgAttrs.y ( String.fromFloat ( cy + 5 ) )
            ]
            [ Html.text player.name ]
            ]
            else []
            )
            |> List.append
                [ Svg.g
                    [ SvgAttrs.transform <|
                        "rotate("
                        ++ String.fromFloat yaw
                        ++ ", "
                        ++ String.fromFloat cx
                        ++ ", "
                        ++ String.fromFloat cy
                        ++ ")"
                    ]
                    [ Svg.path
                        [ SvgAttrs.d <|
                            "M" ++ (String.fromFloat (cx - r)) ++ " " ++ (String.fromFloat cy)
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
                        [ SvgAttrs.d <|
                            "M" ++ (String.fromFloat (cx - r)) ++ " " ++ (String.fromFloat cy)
                            ++ " A " ++ (String.fromFloat r) ++ " " ++ (String.fromFloat r) ++ ", 0, 0, 0, " ++ (String.fromFloat cx) ++ " " ++ (String.fromFloat (cy + r))
                            ++ " L " ++ (String.fromFloat cx) ++ " " ++ (String.fromFloat (cy)) ++ " Z"
                        , SvgAttrs.fill "aqua"
                        ]
                        []
                    ]
                ]
        )
