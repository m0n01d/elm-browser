module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick, onInput)


type alias Model =
    { count : Int
    , step : Int
    , label : String
    , history : List Int
    }


type Msg
    = Increment
    | Decrement
    | Reset
    | SetStep String


init : () -> ( Model, Cmd Msg )
init _ =
    ( { count = 0, step = 1, label = "ready", history = [] }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Increment ->
            ( { model
                | count = model.count + model.step
                , label = "incremented"
                , history = model.count :: model.history
              }
            , Cmd.none
            )

        Decrement ->
            ( { model
                | count = model.count - model.step
                , label = "decremented"
                , history = model.count :: model.history
              }
            , Cmd.none
            )

        Reset ->
            ( { model | count = 0, label = "reset", history = [] }
            , Cmd.none
            )

        SetStep s ->
            ( { model | step = Maybe.withDefault model.step (String.toInt s) }
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    div
        [ style "font-family" "sans-serif"
        , style "padding" "2em"
        , style "max-width" "400px"
        ]
        [ h2 [] [ text "Debugger diff test" ]
        , p [ style "font-size" "3em", style "margin" "0.2em 0" ]
            [ text (String.fromInt model.count) ]
        , p [ style "color" "#888" ] [ text ("label: " ++ model.label) ]
        , div [ style "display" "flex", style "gap" "0.5em", style "margin-bottom" "1em" ]
            [ button [ onClick Decrement ] [ text ("- " ++ String.fromInt model.step) ]
            , button [ onClick Increment ] [ text ("+ " ++ String.fromInt model.step) ]
            , button [ onClick Reset ] [ text "reset" ]
            ]
        , label []
            [ text "step: "
            , input
                [ onInput SetStep
                , Html.Attributes.value (String.fromInt model.step)
                , Html.Attributes.type_ "number"
                , Html.Attributes.min "1"
                , style "width" "4em"
                ]
                []
            ]
        , p [ style "color" "#aaa", style "font-size" "0.85em" ]
            [ text "Open the debugger (bottom-right corner), click messages in the timeline, and watch fields flash yellow when they change." ]
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = always Sub.none
        }
