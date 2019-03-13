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
import Json.Encode exposing (Value)
import Json.Decode exposing (Decoder, field, string, float)
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
subscriptions =
    PortFunnels.subscriptions Process


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
    -- , players = Dict.empty
    , players = Dict.fromList [ ( "dict id", Player "player id" (Coordinates 1 1 1) ( Angles 1 1 1) ) ]
    }
        |> withNoCmd

type alias Player =
    { clientId : ClientId
    , coordinates : Coordinates
    , angles : Angles
    }

type Command = Bullet_impact
             | Decoy_firing
             | Player_death
             | Player_footstep
             | Player_hurt
             | Player_jump
             | Player_spawn
             | Weapon_reload
             | Weapon_zoom
             | Unknown_command

type alias ClientId =
    String

type alias Coordinates =
    { x : Float
    , y : Float
    , z : Float
    }

type alias Angles =
    { ang0 : Float
    , ang1 : Float
    , ang2 : Float
    }


-- UPDATE


type Msg
    = UpdateSend String
    | UpdateUrl String
    | ToggleAutoReopen
    | Connect
    | Close
    | Send
    | Process Value


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

commandDecoder : Decoder String
commandDecoder =
    field "command" string

appendLog : String -> Model -> Model
appendLog str model =
    { model | log = str :: model.log }

handleCommand : String -> String -> Model -> Model
handleCommand command message model =
    case stringToCommand command of
        Player_footstep -> case (decodePlayerFootstep message) of
            Just player -> handlePlayerFootstep model player
            Nothing -> model
        _ -> model

handlePlayerFootstep : Model -> Player -> Model
handlePlayerFootstep model player =
    { model | players = Dict.insert player.clientId player model.players }

decodePlayerFootstep : String -> Maybe Player
decodePlayerFootstep message =
    case Json.Decode.decodeString playerFootstepDecoder message of
        Ok res -> Just res
        Err err -> Nothing

playerFootstepDecoder : Decoder Player
playerFootstepDecoder =
    (Json.Decode.map3 Player
        (field "clientId" clientIdDecoder)
        (field "coordinates" coorinatesDecoder)
        (field "angles" anglesDecoder)
    )

clientIdDecoder : Decoder ClientId
clientIdDecoder =
    string

coorinatesDecoder : Decoder Coordinates
coorinatesDecoder =
    (Json.Decode.map3 Coordinates
        (field "x" float)
        (field "y" float)
        (field "z" float)
    )

anglesDecoder : Decoder Angles
anglesDecoder =
    (Json.Decode.map3 Angles
        (field "ang0" float)
        (field "ang1" float)
        (field "ang2" float)
    )

handleMessage : Model -> String -> Model
handleMessage model message =
    case Json.Decode.decodeString commandDecoder message of
        -- Ok res -> appendLog message model |> handleCommand res message
        Ok res -> appendLog
            ( String.concat
                ( List.map
                    ( \p ->
                        "p coords:" ++ String.fromFloat p.coordinates.x
                        ++ String.fromFloat p.coordinates.y
                        ++ String.fromFloat p.coordinates.z
                    )
                    ( Dict.values model.players )
                )
            )
            model |> handleCommand res message
        Err err -> appendLog ("Received unexpected " ++ message) model

decodeMessage : String -> Command
decodeMessage message =
    case Json.Decode.decodeString commandDecoder message of
        Ok res -> stringToCommand res
        Err err -> Unknown_command

stringToCommand : String -> Command
stringToCommand str =
    case str of
        "bullet_impact" -> Bullet_impact
        "decoy_firing" -> Decoy_firing
        "player_death" -> Player_death
        "player_footstep" -> Player_footstep
        "player_hurt" -> Player_hurt
        "player_jump" -> Player_jump
        "player_spawn" -> Player_spawn
        "weapon_reload" -> Weapon_reload
        "weapon_zoom" -> Weapon_zoom
        _ -> Unknown_command

commandToString : Command -> String
commandToString cmd =
    case cmd of
        Bullet_impact -> "bullet_impact"
        Decoy_firing -> "decoy_firing"
        Player_death -> "player_death"
        Player_footstep-> "player_footstep"
        Player_hurt -> "player_hurt"
        Player_jump -> "player_jump"
        Player_spawn -> "player_spawn"
        Weapon_reload -> "weapon_reload"
        Weapon_zoom -> "weapon_zoom"
        Unknown_command -> "unknown_c"

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
            -- { model | log = ("Received \"" ++ (Result.withDefault "asd" (Json.Decode.decodeString commandDecoder message)) ++ "\"") :: model.log }
            -- { model | log = ("Received \"" ++ commandToString (decodeMessage message) ++ "\"") :: model.log }
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
        [ style "width" "40em"
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
            [ SvgAttrs.width "500"
            , SvgAttrs.height "500"
            ]
            (List.map playerSvg (Dict.values model.players))
            -- [ Svg.circle
            --     [ SvgAttrs.cx <| "20"
            --     , SvgAttrs.cy <| "40"
            --     , SvgAttrs.r <| "4"
            --     , SvgAttrs.fill "orange"
            --     , SvgAttrs.stroke "black"
            --     , SvgAttrs.strokeWidth "2"
            --     ]
            --     []
            -- ]
        , p [] <|
            List.concat
                [ [ b "Log:"
                  , br
                  ]
                , List.intersperse br (List.map text model.log)
                ]
        ]

playerSvg player = Svg.circle
    [ SvgAttrs.cx <| String.fromFloat (player.coordinates.x / 100)
    , SvgAttrs.cy <| String.fromFloat (player.coordinates.y / 100)
    , SvgAttrs.r <| "4"
    , SvgAttrs.fill "orange"
    , SvgAttrs.stroke "black"
    , SvgAttrs.strokeWidth "2"
    ]
    []
