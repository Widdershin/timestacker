module Main exposing (Activity, Model, Msg(..), activityCard, init, main, update, view)

import Browser
import Html exposing (Html, button, div, h1, h2, img, input, p, text)
import Html.Attributes exposing (attribute, class, id, src, style)
import Html.Events exposing (onClick, onInput)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import RemoteData exposing (RemoteData(..), WebData)


find : (a -> Bool) -> List a -> Maybe a
find cond list =
    case list of
        x :: xs ->
            if cond x then
                Just x

            else
                find cond xs

        _ ->
            Nothing


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
    | Editing EditingIdentity ActivityEditState
    | Saving EditingIdentity ActivityEditState (WebData Activity)


type EditingIdentity
    = Existing ActivityId
    | New


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
    | EditActivity ActivityId
    | ChangeActivityColor String
    | ChangeActivityName String
    | StopEditing
    | SaveEditingActivity
    | UpdateSavingActivity (WebData Activity)


editStateFromActivity : Activity -> ActivityEditState
editStateFromActivity activity =
    { name = activity.name
    , color = activity.color
    }


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
            ( { model
                | screen = Activities (Editing New activityEditState)
              }
            , Cmd.none
            )

        EditActivity id ->
            let
                existingActivity =
                    RemoteData.map
                        (find (\a -> a.id == id))
                        model.activities

                editState =
                    RemoteData.map
                        (Maybe.map editStateFromActivity)
                        existingActivity
            in
            case editState of
                Success (Just e) ->
                    ( { model
                        | screen = Activities (Editing (Existing id) e)
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ChangeActivityName name ->
            case model.screen of
                Activities (Editing id editState) ->
                    let
                        newEditState =
                            { editState
                                | name = name
                            }
                    in
                    ( { model
                        | screen = Activities (Editing id newEditState)
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ChangeActivityColor color ->
            case model.screen of
                Activities (Editing id editState) ->
                    let
                        newEditState =
                            { editState
                                | color = color
                            }
                    in
                    ( { model
                        | screen = Activities (Editing id newEditState)
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        SaveEditingActivity ->
            case model.screen of
                Activities (Editing New editState) ->
                    ( { model
                        | screen = Activities (Saving New editState Loading)
                      }
                    , newActivityRequest model.flags.csrfToken editState
                        |> RemoteData.sendRequest
                        |> Cmd.map UpdateSavingActivity
                    )

                Activities (Editing (Existing id) editState) ->
                    ( { model
                        | screen =
                            Activities (Saving (Existing id) editState Loading)
                      }
                    , updateActivityRequest model.flags.csrfToken id editState
                        |> RemoteData.sendRequest
                        |> Cmd.map UpdateSavingActivity
                    )

                _ ->
                    ( model, Cmd.none )

        StopEditing ->
            ( { model | screen = Activities Passive }, Cmd.none )

        UpdateSavingActivity remoteActivity ->
            case model.screen of
                Activities (Saving editIdentity editState _) ->
                    case ( remoteActivity, model.activities ) of
                        ( Success savedActivity, Success activities ) ->
                            ( { model
                                | screen = Activities Passive
                                , activities =
                                    Success
                                        (updateActivities
                                            editIdentity
                                            savedActivity
                                            activities
                                        )
                              }
                            , Cmd.none
                            )

                        _ ->
                            ( { model
                                | screen =
                                    Activities
                                        (Saving
                                            editIdentity
                                            editState
                                            remoteActivity
                                        )
                              }
                            , Cmd.none
                            )

                _ ->
                    ( model, Cmd.none )


updateActivities : EditingIdentity -> Activity -> List Activity -> List Activity
updateActivities editIdentity updatedActivity activities =
    case editIdentity of
        New ->
            activities ++ [ updatedActivity ]

        Existing id ->
            List.map
                (\a ->
                    if a.id == id then
                        updatedActivity

                    else
                        a
                )
                activities


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


updateActivityRequest :
    String
    -> ActivityId
    -> ActivityEditState
    -> Http.Request Activity
updateActivityRequest token id editState =
    Http.request
        { method = "PUT"
        , headers =
            [ Http.header "X-CSRF-Token" token
            , Http.header "Accept" "application/json"
            ]
        , url = "/activities/" ++ id
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
                            Editing New new ->
                                Just (renderEditActivity new)

                            Saving New new remoteStatus ->
                                Just (renderSavingActivity new remoteStatus)

                            _ ->
                                Nothing

                    editingId =
                        case activityState of
                            Editing (Existing id) state ->
                                Just ( Existing id, state )

                            _ ->
                                Nothing
                in
                [ h1 [] [ text "Activities" ]
                , renderActivities model.activities activityState
                , renderQueue
                , button
                    [ class "control new-activity"
                    , onClick NewActivity
                    ]
                    [ text "New Activity" ]
                , button
                    [ class "control go"
                    ]
                    [ text "Start" ]
                ]

            Timer ->
                [ h1 [] [ text "Timer" ]
                , renderActivities model.activities Passive
                , renderQueue
                , renderControls
                ]


renderActivities :
    WebData (List Activity)
    -> ActivitiesMode
    -> Html Msg
renderActivities remoteActivities activitiesMode =
    let
        newActivity =
            case activitiesMode of
                Editing New new ->
                    [ renderEditActivity new ]

                Saving New new remoteStatus ->
                    [ renderSavingActivity new remoteStatus ]

                _ ->
                    []

        renderActivity activity =
            case activitiesMode of
                Editing (Existing id) state ->
                    if id == activity.id then
                        renderEditActivity state

                    else
                        activityCard activity

                Saving (Existing id) state remoteStatus ->
                    if id == activity.id then
                        renderSavingActivity state remoteStatus

                    else
                        activityCard activity

                _ ->
                    activityCard activity
    in
    case remoteActivities of
        NotAsked ->
            text ""

        Loading ->
            text "Loading activities..."

        Success activities ->
            div [ class "activities" ] (List.map renderActivity activities ++ newActivity)

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
    div
        [ class "activity"
        , style "background" activity.color
        ]
        [ h2
            [ class "name" ]
            [ text activity.name ]
        , button
            [ class "edit"
            , onClick (EditActivity activity.id)
            ]
            [ text "Edit" ]
        ]


renderEditActivity : ActivityEditState -> Html Msg
renderEditActivity activity =
    div
        [ class "activity new"
        , style "background-color" activity.color
        ]
        [ input
            [ class "name"
            , onInput ChangeActivityName
            , attribute "value" activity.name
            ]
            []
        , input
            [ class "color"
            , attribute "type" "color"
            , attribute "value" activity.color
            , onInput ChangeActivityColor
            ]
            []
        , button
            [ class "save-activity"
            , onClick SaveEditingActivity
            ]
            [ text "Done" ]
        , button
            [ class "save-activity"
            , onClick StopEditing
            ]
            [ text "Cancel" ]
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
