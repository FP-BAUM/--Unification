
module Lexer.Categories(
         isDigit, isInteger, isWhitespace,
         isPunctuation, punctuationType,
         isKeyword, keywordType, isIdent
       ) where

import qualified Data.Map as M
import Data.Char(isPrint)

import Lexer.Token(TokenType(..))

punctuation :: M.Map Char TokenType
punctuation = M.fromList [
  ('.', T_Dot),
  ('(', T_LParen),
  (')', T_RParen),
  ('{', T_LBrace),
  ('}', T_RBrace),
  (';', T_Semicolon)
 ]

keywords :: M.Map String TokenType
keywords = M.fromList [
  ("class", T_Class),
  (":", T_Colon),
  ("data", T_Data),
  ("=", T_Eq),
  ("import", T_Import),
  ("in", T_In),
  ("infix", T_Infix),
  ("infixl", T_Infixl),
  ("infixr", T_Infixr),
  ("instance", T_Instance),
  ("\\", T_Lambda),
  ("let", T_Let),
  ("module", T_Module),
  ("where", T_Where)
 ]

isDigit :: Char -> Bool
isDigit c = '0' <= c && c <= '9'

isInteger :: String -> Bool
isInteger s = not (null s) && all isDigit s

isWhitespace :: Char -> Bool
isWhitespace c = c `elem` [' ', '\t', '\r', '\n']

isPunctuation :: Char -> Bool
isPunctuation c = M.member c punctuation

punctuationType :: Char -> TokenType
punctuationType c = M.findWithDefault undefined c punctuation

isKeyword :: String -> Bool
isKeyword s = M.member s keywords

keywordType :: String -> TokenType
keywordType s = M.findWithDefault undefined s keywords

isIdent :: Char -> Bool
isIdent c = isPrint c && not (isWhitespace c) && not (isPunctuation c)
