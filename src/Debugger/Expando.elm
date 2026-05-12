module Debugger.Expando exposing
  ( Expando
  , Diff
  , Msg
  , init
  , merge
  , computeDiff
  , update
  , view
  )


import Dict exposing (Dict)
import Elm.Kernel.Debugger
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class, style)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Json



-- MODEL


type Expando
  = S String
  | Primitive String
  | Sequence SeqType Bool (List Expando)
  | Dictionary Bool (List (Expando, Expando))
  | Record Bool (Dict String Expando)
  | Constructor (Maybe String) Bool (List Expando)


type SeqType
  = ListSeq
  | SetSeq
  | ArraySeq


seqTypeToString : Int -> SeqType -> String
seqTypeToString n seqType =
  case seqType of
    ListSeq ->
      "List(" ++ String.fromInt n ++ ")"

    SetSeq ->
      "Set(" ++ String.fromInt n ++ ")"

    ArraySeq ->
      "Array(" ++ String.fromInt n ++ ")"



-- DIFF


type Diff
  = Same
  | Changed
  | DiffRecord (Dict String Diff)
  | DiffSequence (List Diff)
  | DiffDictionary (List ( Diff, Diff ))
  | DiffConstructor (List Diff)


computeDiff : Expando -> Expando -> Diff
computeDiff old new =
  case ( old, new ) of
    ( S a, S b ) ->
      if a == b then Same else Changed

    ( Primitive a, Primitive b ) ->
      if a == b then Same else Changed

    ( Sequence _ _ aItems, Sequence _ _ bItems ) ->
      let
        paired = List.map2 computeDiff aItems bItems
        extras = List.repeat (max 0 (List.length bItems - List.length aItems)) Changed
        diffs  = paired ++ extras
      in
      if List.all ((==) Same) diffs then Same else DiffSequence diffs

    ( Dictionary _ aKvs, Dictionary _ bKvs ) ->
      let
        pairDiff ( ok, ov ) ( nk, nv ) = ( computeDiff ok nk, computeDiff ov nv )
        paired = List.map2 pairDiff aKvs bKvs
        extras = List.repeat (max 0 (List.length bKvs - List.length aKvs)) ( Changed, Changed )
        diffs  = paired ++ extras
        allSame = List.all (\( dk, dv ) -> dk == Same && dv == Same) diffs
      in
      if allSame then Same else DiffDictionary diffs

    ( Record _ aFields, Record _ bFields ) ->
      let
        diffField key bVal =
          case Dict.get key aFields of
            Nothing   -> Changed
            Just aVal -> computeDiff aVal bVal
        diffs   = Dict.map diffField bFields
        allSame = List.all ((==) Same) (Dict.values diffs)
      in
      if allSame then Same else DiffRecord diffs

    ( Constructor aName _ aArgs, Constructor bName _ bArgs ) ->
      if aName /= bName then
        Changed
      else
        let
          paired = List.map2 computeDiff aArgs bArgs
          extras = List.repeat (max 0 (List.length bArgs - List.length aArgs)) Changed
          diffs  = paired ++ extras
        in
        if List.all ((==) Same) diffs then Same else DiffConstructor diffs

    _ ->
      Changed


-- Extract the diff for item i in a sequence or constructor arg list
itemDiff : Int -> Maybe Diff -> Maybe Diff
itemDiff i maybeDiff =
  case maybeDiff of
    Just (DiffSequence diffs) ->
      List.head (List.drop i diffs)

    Just (DiffConstructor diffs) ->
      List.head (List.drop i diffs)

    _ ->
      Nothing


-- Extract the diff for a named record field
fieldDiff : String -> Maybe Diff -> Maybe Diff
fieldDiff key maybeDiff =
  case maybeDiff of
    Just (DiffRecord diffs) ->
      Dict.get key diffs

    _ ->
      Nothing


-- Extract (keyDiff, valDiff) for a dict entry at index i
dictKVDiff : Int -> Maybe Diff -> ( Maybe Diff, Maybe Diff )
dictKVDiff i maybeDiff =
  case maybeDiff of
    Just (DiffDictionary diffs) ->
      case List.drop i diffs of
        ( dk, dv ) :: _ -> ( Just dk, Just dv )
        []              -> ( Nothing, Nothing )

    _ ->
      ( Nothing, Nothing )


-- Return the CSS class for a node.
-- Leaf nodes that are `Just Changed` use Html.Keyed for DOM recreation instead of this.
changedClass : Maybe Diff -> Html.Attribute msg
changedClass maybeDiff =
  case maybeDiff of
    Just Changed -> class "elm-debugger-changed"
    Just Same    -> class ""
    Just _       -> class "elm-debugger-changed-ancestor"
    Nothing      -> class ""



-- INITIALIZE


init : a -> Expando
init value =
  initHelp True (Elm.Kernel.Debugger.init value)


initHelp : Bool -> Expando -> Expando
initHelp isOuter expando =
  case expando of
    S _ ->
      expando

    Primitive _ ->
      expando

    Sequence seqType isClosed items ->
      if isOuter then
        Sequence seqType False (List.map (initHelp False) items)

      else if List.length items <= 8 then
        Sequence seqType False items

      else
        expando

    Dictionary isClosed keyValuePairs ->
      if isOuter then
        Dictionary False (List.map (\( k, v ) -> ( k, initHelp False v )) keyValuePairs)

      else if List.length keyValuePairs <= 8 then
        Dictionary False keyValuePairs

      else
        expando

    Record isClosed entries ->
      if isOuter then
        Record False (Dict.map (\_ v -> initHelp False v) entries)

      else if Dict.size entries <= 4 then
        Record False entries

      else
        expando

    Constructor maybeName isClosed args ->
      if isOuter then
        Constructor maybeName False (List.map (initHelp False) args)

      else if List.length args <= 4 then
        Constructor maybeName False args

      else
        expando



-- PRESERVE OLD EXPANDO STATE (open/closed)


merge : a -> Expando -> Expando
merge value expando =
  mergeHelp expando (Elm.Kernel.Debugger.init value)


mergeHelp : Expando -> Expando -> Expando
mergeHelp old new =
  case (old, new) of
    (_, S _) ->
      new

    (_, Primitive _) ->
      new

    (Sequence _ isClosed oldValues, Sequence seqType _ newValues) ->
      Sequence seqType isClosed (mergeListHelp oldValues newValues)

    (Dictionary isClosed _, Dictionary _ keyValuePairs) ->
      Dictionary isClosed keyValuePairs

    (Record isClosed oldDict, Record _ newDict) ->
      Record isClosed <| Dict.map (mergeDictHelp oldDict) newDict

    (Constructor _ isClosed oldValues, Constructor maybeName _ newValues) ->
      Constructor maybeName isClosed (mergeListHelp oldValues newValues)

    _ ->
      new


mergeListHelp : List Expando -> List Expando -> List Expando
mergeListHelp olds news =
  case (olds, news) of
    ([], _) ->
      news

    (_, []) ->
      news

    (x :: xs, y :: ys) ->
      mergeHelp x y :: mergeListHelp xs ys


mergeDictHelp : Dict String Expando -> String -> Expando -> Expando
mergeDictHelp oldDict key value =
  case Dict.get key oldDict of
    Nothing ->
      value

    Just oldValue ->
      mergeHelp oldValue value



-- UPDATE


type Msg
  = Toggle
  | Index Redirect Int Msg
  | Field String Msg


type Redirect
  = None
  | Key
  | Value


update : Msg -> Expando -> Expando
update msg value =
  case value of
    S _ ->
      -- Debug.crash "nothing changes a primitive"
      value

    Primitive _ ->
      -- Debug.crash "nothing changes a primitive"
      value

    Sequence seqType isClosed valueList ->
      case msg of
        Toggle ->
          Sequence seqType (not isClosed) valueList

        Index None index subMsg ->
          Sequence seqType isClosed <| updateIndex index (update subMsg) valueList

        Index _ _ _ ->
          -- Debug.crash "no redirected indexes on sequences"
          value

        Field _ _ ->
          -- Debug.crash "no field on sequences"
          value

    Dictionary isClosed keyValuePairs ->
      case msg of
        Toggle ->
          Dictionary (not isClosed) keyValuePairs

        Index redirect index subMsg ->
          case redirect of
            None ->
              -- Debug.crash "must have redirect for dictionaries"
              value

            Key ->
              Dictionary isClosed <|
                updateIndex index (\( k, v ) -> ( update subMsg k, v )) keyValuePairs

            Value ->
              Dictionary isClosed <|
                updateIndex index (\( k, v ) -> ( k, update subMsg v )) keyValuePairs

        Field _ _ ->
          -- Debug.crash "no field for dictionaries"
          value

    Record isClosed valueDict ->
      case msg of
        Toggle ->
          Record (not isClosed) valueDict

        Index _ _ _ ->
          -- Debug.crash "no index for records"
          value

        Field field subMsg ->
          Record isClosed (Dict.update field (updateField subMsg) valueDict)

    Constructor maybeName isClosed valueList ->
      case msg of
        Toggle ->
          Constructor maybeName (not isClosed) valueList

        Index None index subMsg ->
          Constructor maybeName isClosed <|
            updateIndex index (update subMsg) valueList

        Index _ _ _ ->
          -- Debug.crash "no redirected indexes on sequences"
          value

        Field _ _ ->
          -- Debug.crash "no field for constructors"
          value


updateIndex : Int -> (a -> a) -> List a -> List a
updateIndex n func list =
  case list of
    [] ->
      []

    x :: xs ->
      if n <= 0
      then func x :: xs
      else x :: updateIndex (n - 1) func xs


updateField : Msg -> Maybe Expando -> Maybe Expando
updateField msg maybeExpando =
  case maybeExpando of
    Nothing ->
      -- Debug.crash "key does not exist"
      maybeExpando

    Just expando ->
      Just (update msg expando)



-- VIEW


view : Maybe String -> Expando -> Maybe Diff -> Bool -> Html Msg
view maybeKey expando maybeDiff flip =
  case expando of
    S stringRep ->
      let content = lineStarter maybeKey Nothing [ span [ red ] [ text stringRep ] ]
      in
      case maybeDiff of
        Just Changed ->
          Html.Keyed.node "div" (leftPad maybeKey)
            [ ( if flip then "1" else "0", div [ class "elm-debugger-changed" ] content ) ]
        _ ->
          div (leftPad maybeKey ++ [ changedClass maybeDiff ]) content

    Primitive stringRep ->
      let content = lineStarter maybeKey Nothing [ span [ blue ] [ text stringRep ] ]
      in
      case maybeDiff of
        Just Changed ->
          Html.Keyed.node "div" (leftPad maybeKey)
            [ ( if flip then "1" else "0", div [ class "elm-debugger-changed" ] content ) ]
        _ ->
          div (leftPad maybeKey ++ [ changedClass maybeDiff ]) content

    Sequence seqType isClosed valueList ->
      viewSequence maybeKey seqType isClosed valueList maybeDiff flip

    Dictionary isClosed keyValuePairs ->
      viewDictionary maybeKey isClosed keyValuePairs maybeDiff flip

    Record isClosed valueDict ->
      viewRecord maybeKey isClosed valueDict maybeDiff flip

    Constructor maybeName isClosed valueList ->
      viewConstructor maybeKey maybeName isClosed valueList maybeDiff flip



-- VIEW SEQUENCE


viewSequence : Maybe String -> SeqType -> Bool -> List Expando -> Maybe Diff -> Bool -> Html Msg
viewSequence maybeKey seqType isClosed valueList maybeDiff flip =
  let
    starter = seqTypeToString (List.length valueList) seqType
  in
  div (leftPad maybeKey ++ [ changedClass maybeDiff ])
    [ div [ onClick Toggle ] (lineStarter maybeKey (Just isClosed) [ text starter ])
    , if isClosed then text "" else viewSequenceOpen valueList maybeDiff flip
    ]


viewSequenceOpen : List Expando -> Maybe Diff -> Bool -> Html Msg
viewSequenceOpen values maybeDiff flip =
  div [] (List.indexedMap (\i v -> viewConstructorEntry i v (itemDiff i maybeDiff) flip) values)



-- VIEW DICTIONARY


viewDictionary : Maybe String -> Bool -> List (Expando, Expando) -> Maybe Diff -> Bool -> Html Msg
viewDictionary maybeKey isClosed keyValuePairs maybeDiff flip =
  let
    starter = "Dict(" ++ String.fromInt (List.length keyValuePairs) ++ ")"
  in
  div (leftPad maybeKey ++ [ changedClass maybeDiff ])
    [ div [ onClick Toggle ] (lineStarter maybeKey (Just isClosed) [ text starter ])
    , if isClosed then text "" else viewDictionaryOpen keyValuePairs maybeDiff flip
    ]


viewDictionaryOpen : List (Expando, Expando) -> Maybe Diff -> Bool -> Html Msg
viewDictionaryOpen keyValuePairs maybeDiff flip =
  div [] (List.indexedMap (\i kv -> viewDictionaryEntry i kv (dictKVDiff i maybeDiff) flip) keyValuePairs)


viewDictionaryEntry : Int -> (Expando, Expando) -> ( Maybe Diff, Maybe Diff ) -> Bool -> Html Msg
viewDictionaryEntry index ( key, value ) ( kDiff, vDiff ) flip =
  case key of
    S stringRep ->
      Html.map (Index Value index) (view (Just stringRep) value vDiff flip)

    Primitive stringRep ->
      Html.map (Index Value index) (view (Just stringRep) value vDiff flip)

    _ ->
      div []
        [ Html.map (Index Key index) (view (Just "key") key kDiff flip)
        , Html.map (Index Value index) (view (Just "value") value vDiff flip)
        ]



-- VIEW RECORD


viewRecord : Maybe String -> Bool -> Dict String Expando -> Maybe Diff -> Bool -> Html Msg
viewRecord maybeKey isClosed record maybeDiff flip =
  let
    (start, middle, end) =
      if isClosed then
        (Tuple.second (viewTinyRecord record), text "", text "")
      else
        ([ text "{" ], viewRecordOpen record maybeDiff flip, div (leftPad (Just ())) [ text "}" ])
  in
  div (leftPad maybeKey ++ [ changedClass maybeDiff ])
    [ div [ onClick Toggle ] (lineStarter maybeKey (Just isClosed) start)
    , middle
    , end
    ]


viewRecordOpen : Dict String Expando -> Maybe Diff -> Bool -> Html Msg
viewRecordOpen record maybeDiff flip =
  div [] (List.map (\( k, v ) -> viewRecordEntry k v (fieldDiff k maybeDiff) flip) (Dict.toList record))


viewRecordEntry : String -> Expando -> Maybe Diff -> Bool -> Html Msg
viewRecordEntry field value fDiff flip =
  Html.map (Field field) (view (Just field) value fDiff flip)



-- VIEW CONSTRUCTOR


viewConstructor : Maybe String -> Maybe String -> Bool -> List Expando -> Maybe Diff -> Bool -> Html Msg
viewConstructor maybeKey maybeName isClosed valueList maybeDiff flip =
  let
    tinyArgs = List.map (Tuple.second << viewExtraTiny) valueList

    description =
      case (maybeName, tinyArgs) of
        (Nothing  , []     ) -> [ text "()" ]
        (Nothing  , x :: xs) -> text "( " :: span [] x :: List.foldr (\args rest -> text ", " :: span [] args :: rest) [ text " )" ] xs
        (Just name, []     ) -> [ text name ]
        (Just name, x :: xs) -> text (name ++ " ") :: span [] x :: List.foldr (\args rest -> text " " :: span [] args :: rest) [] xs

    arg0Diff = itemDiff 0 maybeDiff

    (maybeIsClosed, openHtml) =
        case valueList of
          [] ->
            (Nothing, div [] [])

          [ entry ] ->
            case entry of
              S _ ->
                (Nothing, div [] [])

              Primitive _ ->
                (Nothing, div [] [])

              Sequence _ _ subValueList ->
                ( Just isClosed
                , if isClosed then div [] [] else
                    Html.map (Index None 0) (viewSequenceOpen subValueList arg0Diff flip)
                )

              Dictionary _ keyValuePairs ->
                ( Just isClosed
                , if isClosed then div [] [] else
                    Html.map (Index None 0) (viewDictionaryOpen keyValuePairs arg0Diff flip)
                )

              Record _ record ->
                  ( Just isClosed
                  , if isClosed then div [] [] else
                      Html.map (Index None 0) (viewRecordOpen record arg0Diff flip)
                  )

              Constructor _ _ subValueList ->
                  ( Just isClosed
                  , if isClosed then div [] [] else
                      Html.map (Index None 0) (viewConstructorOpen subValueList arg0Diff flip)
                  )

          _ ->
            ( Just isClosed
            , if isClosed then div [] [] else viewConstructorOpen valueList maybeDiff flip
            )

    -- When nothing is expandable (maybeIsClosed == Nothing), the entire value is shown
    -- inline in the summary text. Escalate any structural diff to Changed so the row
    -- animates (e.g. Time.Posix, unit types, single-primitive constructors like Maybe.Just 42).
    effectiveDiff =
      case maybeIsClosed of
        Nothing ->
          case maybeDiff of
            Just (DiffConstructor _) -> Just Changed
            _ -> maybeDiff
        Just _ -> maybeDiff
  in
  case effectiveDiff of
    Just Changed ->
      Html.Keyed.node "div" (leftPad maybeKey)
        [ ( if flip then "1" else "0"
          , div [ class "elm-debugger-changed" ]
              [ div [ onClick Toggle ] (lineStarter maybeKey maybeIsClosed description)
              , openHtml
              ]
          )
        ]
    _ ->
      div (leftPad maybeKey ++ [ changedClass effectiveDiff ])
        [ div [ onClick Toggle ] (lineStarter maybeKey maybeIsClosed description)
        , openHtml
        ]


viewConstructorOpen : List Expando -> Maybe Diff -> Bool -> Html Msg
viewConstructorOpen valueList maybeDiff flip =
  div [] (List.indexedMap (\i v -> viewConstructorEntry i v (itemDiff i maybeDiff) flip) valueList)


viewConstructorEntry : Int -> Expando -> Maybe Diff -> Bool -> Html Msg
viewConstructorEntry index value maybeDiff flip =
  Html.map (Index None index) (view (Just (String.fromInt index)) value maybeDiff flip)



-- VIEW TINY


viewTiny : Expando -> ( Int, List (Html msg) )
viewTiny value =
  case value of
    S stringRep ->
      let
        str = elideMiddle stringRep
      in
      ( String.length str
      , [ span [ red ] [ text str ] ]
      )

    Primitive stringRep ->
      ( String.length stringRep
      , [ span [ blue ] [ text stringRep ] ]
      )

    Sequence seqType _ valueList ->
      viewTinyHelp <| seqTypeToString (List.length valueList) seqType

    Dictionary _ keyValuePairs ->
      viewTinyHelp <| "Dict(" ++ String.fromInt (List.length keyValuePairs) ++ ")"

    Record _ record ->
      viewTinyRecord record

    Constructor maybeName _ [] ->
      viewTinyHelp <| Maybe.withDefault "Unit" maybeName

    Constructor maybeName _ valueList ->
      viewTinyHelp <|
        case maybeName of
          Nothing -> "Tuple(" ++ String.fromInt (List.length valueList) ++ ")"
          Just name -> name ++ " …"


viewTinyHelp : String -> ( Int, List (Html msg) )
viewTinyHelp str =
  (String.length str, [ text str ])


elideMiddle : String -> String
elideMiddle str =
  if String.length str <= 18
  then str
  else String.left 8 str ++ "..." ++ String.right 8 str



-- VIEW TINY RECORDS


viewTinyRecord : Dict String Expando -> ( Int, List (Html msg) )
viewTinyRecord record =
  if Dict.isEmpty record then
    (2, [ text "{}" ])
  else
    viewTinyRecordHelp 0 "{ " (Dict.toList record)


viewTinyRecordHelp : Int -> String -> List ( String, Expando ) -> ( Int, List (Html msg) )
viewTinyRecordHelp length starter entries =
  case entries of
    [] ->
        (length + 2, [ text " }" ])

    (field, value) :: rest ->
      let
        fieldLen = String.length field
        (valueLen, valueHtmls) = viewExtraTiny value
        newLength = length + fieldLen + valueLen + 5
      in
      if newLength > 60 then
        (length + 4, [ text ", … }" ])
      else
        let
          (finalLength, otherHtmls) = viewTinyRecordHelp newLength ", " rest
        in
        ( finalLength
        , text starter
            :: span [ purple ] [ text field ]
            :: text " = "
            :: span [] valueHtmls
            :: otherHtmls
        )


viewExtraTiny : Expando -> ( Int, List (Html msg) )
viewExtraTiny value =
  case value of
    Record _ record ->
      viewExtraTinyRecord 0 "{" (Dict.keys record)

    _ ->
      viewTiny value


viewExtraTinyRecord : Int -> String -> List String -> ( Int, List (Html msg) )
viewExtraTinyRecord length starter entries =
  case entries of
    [] ->
      (length + 1, [ text "}" ])

    field :: rest ->
      let
        nextLength = length + String.length field + 1
      in
      if nextLength > 18 then
        (length + 2, [ text "…}" ])

      else
        let
          (finalLength, otherHtmls) = viewExtraTinyRecord nextLength "," rest
        in
        ( finalLength
        , text starter :: span [ purple ] [ text field ] :: otherHtmls
        )



-- VIEW HELPERS


lineStarter : Maybe String -> Maybe Bool -> List (Html msg) -> List (Html msg)
lineStarter maybeKey maybeIsClosed description =
  let
    arrow =
      case maybeIsClosed of
        Nothing    -> makeArrow ""
        Just True  -> makeArrow "▸"
        Just False -> makeArrow "▾"
  in
  case maybeKey of
    Nothing ->
      arrow :: description

    Just key ->
      arrow :: span [ purple ] [ text key ] :: text " = " :: description


makeArrow : String -> Html msg
makeArrow arrow =
  span
    [ style "color" "#777"
    , style "padding-left" "2ch"
    , style "width" "2ch"
    , style "display" "inline-block"
    ]
    [ text arrow ]


leftPad : Maybe a -> List (Html.Attribute msg)
leftPad maybeKey =
  case maybeKey of
    Nothing -> []
    Just _  -> [ style "padding-left" "4ch" ]


red : Html.Attribute msg
red =
  style "color" "rgb(196, 26, 22)"


blue : Html.Attribute msg
blue =
  style "color" "rgb(28, 0, 207)"


purple : Html.Attribute msg
purple =
  style "color" "rgb(136, 19, 145)"
