module Main exposing (Activity, Model, Msg(..), activityCard, init, main, update, view)

import Browser
import Html exposing (Html, button, div, h1, h2, img, input, p, text)
import Html.Attributes exposing (attribute, class, id, src, style)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import RemoteData exposing (RemoteData(..), WebData)


type alias Model =
    { flags : Flags
    , activities : WebData (List Activity)
    , screen : Screen
    }


type Screen
    = Activities ActivitiesMode
    | Timer


type ActivitiesMode
    = Passive
    | Creating ActivityEditState
    | Saving ActivityEditState (WebData Activity)
    | Editing


type alias Flags =
    { csrfToken : String }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { flags = flags, activities = NotAsked, screen = Activities Passive }
    , activitiesRequest flags.csrfToken
        |> RemoteData.sendRequest
        |> Cmd.map UpdateActivities
    )


type alias ActivityId =
    String


type alias ActivityEditState =
    { name : String
    , color : String
    }


type alias Activity =
    { id : ActivityId
    , name : String
    , color : String
    }


type Msg
    = NoOp
    | UpdateActivities (WebData (List Activity))
    | NewActivity
    | ChangeNewActivityColor String
    | ChangeNewActivityName String
    | SaveNewActivity
    | DiscardNewActivity
    | UpdateSavingActivity (WebData Activity)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        UpdateActivities activities ->
            ( { model | activities = activities }, Cmd.none )

        NewActivity ->
            let
                activityEditState =
                    { name = ""
                    , color = "#663399"
                    }
            in
            ( { model | screen = Activities (Creating activityEditState) }, Cmd.none )

        ChangeNewActivityName name ->
            case model.screen of
                Activities (Creating editState) ->
                    let
                        newEditState =
                            { editState
                                | name = name
                            }
                    in
                    ( { model | screen = Activities (Creating newEditState) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ChangeNewActivityColor color ->
            case model.screen of
                Activities (Creating editState) ->
                    let
                        newEditState =
                            { editState
                                | color = color
                            }
                    in
                    ( { model | screen = Activities (Creating newEditState) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SaveNewActivity ->
            case model.screen of
                Activities (Creating editState) ->
                    ( { model | screen = Activities (Saving editState NotAsked) }
                    , newActivityRequest model.flags.csrfToken editState |> RemoteData.sendRequest |> Cmd.map UpdateSavingActivity
                    )

                _ ->
                    ( model, Cmd.none )

        DiscardNewActivity ->
            case model.screen of
                Activities (Creating editState) ->
                    ( { model | screen = Activities Passive }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        UpdateSavingActivity remoteActivity ->
            case model.screen of
                Activities (Saving editState _) ->
                    case ( remoteActivity, model.activities ) of
                        ( Success savedActivity, Success activities ) ->
                            ( { model | screen = Activities Passive, activities = Success (activities ++ [ savedActivity ]) }, Cmd.none )

                        _ ->
                            ( { model | screen = Activities (Saving editState remoteActivity) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )


activitiesRequest : String -> Http.Request (List Activity)
activitiesRequest token =
    Http.request
        { method = "GET"
        , headers =
            [ Http.header "X-CSRF-Token" token
            , Http.header "Accept" "application/json"
            ]
        , url = "/activities"
        , body = Http.emptyBody
        , expect = Http.expectJson decodeActivities
        , timeout = Nothing
        , withCredentials = False
        }


newActivityRequest : String -> ActivityEditState -> Http.Request Activity
newActivityRequest token editState =
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "X-CSRF-Token" token
            , Http.header "Accept" "application/json"
            ]
        , url = "/activities"
        , body = Http.jsonBody (encodeActivity editState)
        , expect = Http.expectJson decodeActivity
        , timeout = Nothing
        , withCredentials = False
        }


decodeActivity : Decoder Activity
decodeActivity =
    let
        makeActivity id name color =
            { id = id
            , name = name
            , color = color
            }
    in
    Decode.map3 makeActivity
        (Decode.field "id" Decode.int |> Decode.map String.fromInt)
        (Decode.field "name" Decode.string)
        (Decode.field "color" Decode.string)


encodeActivity : ActivityEditState -> Encode.Value
encodeActivity editState =
    Encode.object
        [ ( "activity"
          , Encode.object
                [ ( "name", Encode.string editState.name )
                , ( "color", Encode.string editState.color )
                ]
          )
        ]


decodeActivities : Decoder (List Activity)
decodeActivities =
    Decode.list decodeActivity


maybeToDecoder : String -> Maybe a -> Decoder a
maybeToDecoder error maybe =
    case maybe of
        Just a ->
            Decode.succeed a

        Nothing ->
            Decode.fail error


view : Model -> Html Msg
view model =
    div [ id "wrapper", class "view" ] <|
        case model.screen of
            Activities activityState ->
                let
                    newActivity =
                        case activityState of
                            Creating new ->
                                Just (renderEditActivity new)

                            Saving new remoteStatus ->
                                Just (renderSavingActivity new remoteStatus)

                            _ ->
                                Nothing
                in
                [ h1 [] [ text "Activities" ]
                , renderActivities model.activities newActivity
                , renderQueue
                , button [ class "control new-activity", onClick NewActivity ] [ text "New Activity" ]
                , button [ class "control go" ] [ text "Start" ]
                ]

            Timer ->
                [ h1 [] [ text "Timer" ]
                , renderActivities model.activities Nothing
                , renderQueue
                , renderControls
                ]


renderActivities : WebData (List Activity) -> Maybe (Html Msg) -> Html Msg
renderActivities remoteActivities newActivity =
    let
        possibleNewActivity =
            case newActivity of
                Just editState ->
                    [ editState ]

                Nothing ->
                    []
    in
    case remoteActivities of
        NotAsked ->
            text ""

        Loading ->
            text "Loading activities..."

        Success activities ->
            div [ class "activities" ] (List.map activityCard activities ++ possibleNewActivity)

        Failure _ ->
            text "Error"


renderQueue : Html Msg
renderQueue =
    div [ class "queue" ]
        [ div [ class "queue-blocks" ]
            [ div [ class "blocks" ] []
            ]
        ]


renderControls : Html Msg
renderControls =
    div [ class "controls" ]
        [ button [ class "control go" ] [ text "Start" ] ]


renderBlock : Html Msg
renderBlock =
    div [ class "block" ] []


activityCard : Activity -> Html Msg
activityCard activity =
    div [ class "activity", style "background" (Debug.log "color" activity.color) ]
        [ h2 [ class "name" ] [ text activity.name ] ]


renderEditActivity : ActivityEditState -> Html Msg
renderEditActivity activity =
    div [ class "activity new", style "background-color" activity.color ]
        [ input [ class "name", onInput ChangeNewActivityName ] [ text activity.name ]
        , input [ class "color", attribute "type" "color", attribute "value" activity.color, onInput ChangeNewActivityColor ] []
        , button [ class "save-activity", onClick SaveNewActivity ] [ text "Done" ]
        , button [ class "save-activity", onClick DiscardNewActivity ] [ text "Cancel" ]
        ]


renderSavingActivity : ActivityEditState -> WebData Activity -> Html Msg
renderSavingActivity activity remoteActivity =
    div [ class "activity", style "background-color" activity.color ]
        [ h2 [ class "name" ] [ text activity.name ]
        , div [] [ text (Debug.toString remoteActivity) ]
        ]


main : Program Flags Model Msg
main =
    Browser.element
        { view = view
        , init = init
        , update = update
        , subscriptions = always Sub.none
        }
