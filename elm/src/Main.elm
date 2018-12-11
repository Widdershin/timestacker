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


removeAt : Int -> List a -> List a
removeAt index list =
    case ( compare index 0, list ) of
        ( _, [] ) ->
            []

        ( LT, _ ) ->
            list

        ( EQ, x :: xs ) ->
            xs

        ( GT, x :: xs ) ->
            x :: removeAt (index - 1) xs


type alias Model =
    { flags : Flags
    , activities : WebData (List Activity)
    , screen : Screen
    , queue : List ActivityId
    }


type Screen
    = Activities ActivitiesMode
    | Timer


type ActivitiesMode
    = Passive
    | Editing EditingIdentity ActivityEditState
    | Saving EditingIdentity ActivityEditState (WebData Activity)
    | Archiving ActivityId (WebData Activity)


type EditingIdentity
    = Existing ActivityId
    | New


type alias Flags =
    { csrfToken : String }


type alias Block =
    { color : String, label : String }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { flags = flags
      , activities = NotAsked
      , screen = Activities Passive
      , queue = []
      }
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


type alias QueueIndex =
    Int


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
    | ArchiveActivity ActivityId
    | UpdateArchivingActivity (WebData Activity)
    | QueueActivity ActivityId
    | RemoveQueueBlock QueueIndex
    | StartTimer


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

        ArchiveActivity id ->
            let
                cmd =
                    archiveActivityRequest model.flags.csrfToken id
                        |> RemoteData.sendRequest
                        |> Cmd.map UpdateArchivingActivity
            in
            ( { model | screen = Activities (Archiving id Loading) }, cmd )

        UpdateArchivingActivity remoteActivity ->
            case ( remoteActivity, model.activities ) of
                ( Success archivedActivity, Success activities ) ->
                    ( { model
                        | screen = Activities Passive
                        , activities = Success (List.filter (\a -> a.id /= archivedActivity.id) activities)
                        , queue = List.filter (\id -> id /= archivedActivity.id) model.queue
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        QueueActivity activityId ->
            ( { model | queue = model.queue ++ [ activityId ] }, Cmd.none )

        RemoveQueueBlock index ->
            ( { model | queue = removeAt index model.queue }, Cmd.none )

        StartTimer ->
            ( { model | screen = Timer }, Cmd.none )


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


archiveActivityRequest :
    String
    -> ActivityId
    -> Http.Request Activity
archiveActivityRequest token id =
    Http.request
        { method = "DELETE"
        , headers =
            [ Http.header "X-CSRF-Token" token
            , Http.header "Accept" "application/json"
            ]
        , url = "/activities/" ++ id
        , body = Http.emptyBody
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


makeColorFinder : WebData (List Activity) -> ActivityId -> Maybe Block
makeColorFinder remoteActivities id =
    case remoteActivities of
        Success activities ->
            find (\a -> a.id == id) activities
                |> Maybe.map
                    (\a ->
                        { color = a.color
                        , label =
                            Maybe.withDefault "?" <|
                                Maybe.map String.fromChar <|
                                    List.head <|
                                        String.toList a.name
                        }
                    )

        _ ->
            Nothing


view : Model -> Html Msg
view model =
    div [ id "wrapper", class "view" ] <|
        case model.screen of
            Activities activityState ->
                [ h1 [] [ text "Activities" ]
                , renderActivities model.activities activityState
                , renderQueue model.queue (makeColorFinder model.activities)
                , button
                    [ class "control new-activity"
                    , onClick NewActivity
                    ]
                    [ text "New Activity" ]
                , button
                    [ class "control go"
                    , onClick StartTimer
                    ]
                    [ text "Start" ]
                ]

            Timer ->
                [ h1 [] [ text "Timer" ]
                , renderTimer model.queue
                , renderQueue model.queue (makeColorFinder model.activities)
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
                    [ renderEditActivity Nothing new ]

                Saving New new remoteStatus ->
                    [ renderSavingActivity new remoteStatus ]

                _ ->
                    []

        renderActivity activity =
            case activitiesMode of
                Editing (Existing id) state ->
                    if id == activity.id then
                        renderEditActivity (Just id) state

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


renderTimer : List ActivityId -> Html Msg
renderTimer queue =
    div [] []


renderQueue : List ActivityId -> (ActivityId -> Maybe Block) -> Html Msg
renderQueue queue activityColor =
    let
        renderBlock index activityId =
            let
                blockDetails =
                    Maybe.withDefault { color = "black", label = "?" } (activityColor activityId)
            in
            div
                [ class "block"
                , style "background-color" blockDetails.color
                , onClick (RemoveQueueBlock index)
                ]
                [ text blockDetails.label ]
    in
    div [ class "queue" ]
        [ div [ class "queue-blocks" ]
            [ div [ class "blocks" ] (List.indexedMap renderBlock queue)
            ]
        ]


renderControls : Html Msg
renderControls =
    div [ class "controls" ]
        [ button [ class "control go", onClick StartTimer ] [ text "Start" ] ]


activityCard : Activity -> Html Msg
activityCard activity =
    div
        [ class "activity clickable"
        , style "background" activity.color
        , onClick (QueueActivity activity.id)
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


renderEditActivity : Maybe ActivityId -> ActivityEditState -> Html Msg
renderEditActivity activityId activity =
    let
        archiveButton =
            case activityId of
                Just id ->
                    button
                        [ class "archive"
                        , onClick (ArchiveActivity id)
                        ]
                        [ text "Archive" ]

                Nothing ->
                    text ""
    in
    div
        [ class "activity new"
        , style "background-color" activity.color
        ]
        [ div [ class "edit-row" ]
            [ input
                [ class "name"
                , onInput ChangeActivityName
                , attribute "value" activity.name
                ]
                []
            ]
        , div [ class "edit-row" ]
            [ div [ class "row-part" ]
                [ input
                    [ class "color"
                    , attribute "type" "color"
                    , attribute "value" activity.color
                    , onInput ChangeActivityColor
                    ]
                    []
                , archiveButton
                ]
            , div [ class "row-part right" ]
                [ button
                    [ class "stop-editing"
                    , onClick StopEditing
                    ]
                    [ text "Cancel" ]
                , button
                    [ class "save-activity"
                    , onClick SaveEditingActivity
                    ]
                    [ text "Done" ]
                ]
            ]
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
