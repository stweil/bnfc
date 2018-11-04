{-
    BNF Converter: Non-pretty-printer generator (no "deriving Show" in OCaml...)
    Copyright (C) 2005  Author:  Kristofer Johannisson

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
-}

-- there is no "deriving Show" in OCaml, although there are solutions based
-- on camlp4. Here we generate our own "show module".


module BNFC.Backend.OCaml.CFtoOCamlShow (cf2show) where

import Data.Char(toLower)
import Data.List (intersperse)
import Data.Maybe (fromJust)

import BNFC.CF
import BNFC.Utils
import BNFC.Backend.OCaml.OCamlUtil

cf2show :: String -> String -> CF -> String
cf2show name absMod cf = unlines [
  prologue name absMod,
  integerRule cf,
  doubleRule cf,
  if hasIdent cf then identRule cf else "",
  unlines [ownPrintRule cf own | (own,_) <- tokenPragmas cf],
  rules cf
  ]


prologue :: String -> String -> String
prologue _ absMod = unlines [
  "(* show functions generated by the BNF converter *)\n",
  "open " ++ absMod,
  "",
  "(* use string buffers for efficient string concatenations *)",
  "type showable = Buffer.t -> unit",
  "",
  "let show (s : showable) : string = ",
  "    let init_size = 16 in (* you may want to adjust this *)",
  "    let b = Buffer.create init_size in",
  "    s b;",
  "    Buffer.contents b",
  "    ",
  "let emptyS : showable = fun buf -> ()",
  "",
  "let c2s (c:char) : showable = fun buf -> Buffer.add_char buf c",
  "let s2s (s:string) : showable = fun buf -> Buffer.add_string buf s",
  "",
  "let ( >> ) (s1 : showable) (s2 : showable) : showable = fun buf -> s1 buf; s2 buf",
  "",
  "let showChar (c:char) : showable = fun buf -> ",
  "    Buffer.add_string buf (\"'\" ^ Char.escaped c ^ \"'\")",
  "",
  "let showString (s:string) : showable = fun buf -> ",
  "    Buffer.add_string buf (\"\\\"\" ^ String.escaped s ^ \"\\\"\")",
  "",
  "let showList (showFun : 'a -> showable) (xs : 'a list) : showable = fun buf -> ",
  "    let rec f ys = match ys with",
  "        [] -> ()",
  "      | [y] -> showFun y buf",
  "      | y::ys -> showFun y buf; Buffer.add_string buf \"; \"; f ys ",
  "    in",
  "        Buffer.add_char buf '[';",
  "        f xs;",
  "        Buffer.add_char buf ']'",
  ""
  ]

integerRule _ = "let showInt (i:int) : showable = s2s (string_of_int i)"

doubleRule _ = "let showFloat (f:float) : showable = s2s (string_of_float f)"


identRule cf = ownPrintRule cf (Cat "Ident")

ownPrintRule cf own = unlines $ [
  "let rec" +++ showsFun own +++ "(" ++ show own ++ posn ++ ") : showable = s2s \""
  ++ show own ++ " \" >> showString i"
  ]
 where
   posn = if isPositionCat cf own then " (_,i)" else " i"

-- copy and paste from CFtoTemplate

rules :: CF -> String
rules cf = unlines $ mutualDefs $
  map (\(s,xs) -> case_fun s (map toArgs xs)) $ cf2data cf -- ++ ifList cf s
 where
   toArgs (cons,args) = ((cons, names (map (checkRes . var) args) (0 :: Int)),
                         ruleOf cons)
   names [] _ = []
   names (x:xs) n
     | elem x xs = (x ++ show n) : names xs (n+1)
     | otherwise = x             : names xs n
   var (ListCat c)      = var c ++ "s"
   var (Cat "Ident")    = "id"
   var (Cat "Integer")  = "n"
   var (Cat "String")   = "str"
   var (Cat "Char")     = "c"
   var (Cat "Double")   = "d"
   var cat              = map toLower (show cat)
   checkRes s
        | elem s reservedOCaml = s ++ "'"
        | otherwise              = s
   ruleOf s = fromJust $ lookupRule s (cfgRules cf)

--- case_fun :: Cat -> [(Constructor,Rule)] -> String
case_fun cat xs = unlines [
--  "instance Print" +++ cat +++ "where",
  showsFun cat +++ "(e:" ++ fixType cat ++ ") : showable = match e with",
  unlines $ insertBar $ map (\ ((c,xx),r) ->
    "   " ++ c +++ mkTuple xx +++ "->" +++
    "s2s" +++ show c +++
    case mkRhs xx (snd r) of {[] -> []; str -> ">> c2s ' ' >> " ++ str}
    )
    xs
  ]


mkRhs args its =
  case unwords (intersperse " >> s2s \", \" >> " (mk args its)) of
    [] -> ""
    str -> "c2s '(' >> " ++ str ++ " >> c2s ')'"
 where
  mk args (Left InternalCat : items)      = mk args items
  mk (arg:args) (Left c : items)  = (showsFun c +++ arg)        : mk args items
  mk args       (Right _ : items) = mk args items
  mk _ _ = []

showsFun :: Cat -> String
showsFun c = case c of
    ListCat t -> "showList" +++ showsFun t
    _ -> "show" ++ (fixTypeUpper $ normCat c)
