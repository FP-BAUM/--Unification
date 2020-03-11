module Lexer.Lexer(tokenize) where

import FailState(FailState, getFS, modifyFS, failFS, evalFS)
import Error(Error(..), ErrorType(..))
import Position(Position, initialPosition, updatePosition)

import Syntax.Name(isWellFormedName)
import Lexer.Token(Token(..), TokenType(..))
import Lexer.Categories(
         isDigit, isInteger, isWhitespace,
         isPunctuation, punctuationType,
         isKeyword, keywordType, isIdent,
         isRenaming, renaming
       )
import Lexer.Layout(layout)

tokenize :: FilePath -> String -> Either Error [Token]
tokenize filename source = do
    tokens <- evalFS (tokenizeM source) initialState
    layout tokens
  where initialState = LexerState {
                         statePosition = initialPosition filename source
                       }

---- Lexer monad

data LexerState = LexerState {
                    statePosition :: Position
                  }

type M = FailState LexerState

consumeString :: String -> M ()
consumeString s = modifyFS (\ state -> state {
                     statePosition = updatePosition s (statePosition state)
                   })

consumeChar :: Char -> M ()
consumeChar c = consumeString [c]

currentPosition :: M Position
currentPosition = do state <- getFS
                     return (statePosition state)

---- Tokenizer

tokenizeM :: String -> M [Token]
tokenizeM ""                           = return []
tokenizeM cs@(c : _) | isWhitespace c  = ignoreWhitespace cs
tokenizeM cs@('-' : '-' : _)           = ignoreSingleLineComment cs
tokenizeM cs@('{' : '-' : _)           = ignoreMultiLineComment cs
tokenizeM cs@(c : _) | isPunctuation c = readPunctuation cs
tokenizeM cs@(c : _) | isIdent c       = readName cs
tokenizeM (c : _)                      =
  failM LexerErrorInvalidCharacter
        ("Invalid character: '" ++ show c ++ "'.")

ignoreWhitespace :: String -> M [Token]
ignoreWhitespace [] = tokenizeM []
ignoreWhitespace (c : cs) = do
  consumeChar c
  tokenizeM cs

ignoreSingleLineComment :: String -> M [Token]
ignoreSingleLineComment [] = tokenizeM []
ignoreSingleLineComment ('\n' : cs) = do
  consumeChar '\n'
  tokenizeM cs
ignoreSingleLineComment (c : cs)    = do
  consumeChar c
  ignoreSingleLineComment cs

ignoreMultiLineComment :: String -> M [Token]
ignoreMultiLineComment cs = rec 0 cs
  where
    rec n [] = failM LexerErrorUnclosedComment
                     "Unclosed multiline comment."
    rec n ('{' : '-' : cs) = do
      consumeString "{-"
      rec (n + 1) cs
    rec n ('-' : '}' : cs) = do
      consumeString "-}"
      if n == 1
       then tokenizeM cs
       else rec (n - 1) cs 
    rec n (c : cs) = do
      consumeChar c
      rec n cs

readPunctuation :: String -> M [Token]
readPunctuation []       = error "No punctuation."
readPunctuation (c : cs) = do
  start <- currentPosition
  consumeChar c
  end <- currentPosition
  let t = Token start end (punctuationType c)
   in do ts <- tokenizeM cs
         return (t : ts)

readName :: String -> M [Token]
readName cs = do
  start <- currentPosition
  let (ident, cs') = span isIdent cs in do
    consumeString ident
    end <- currentPosition
    typ <- nameType ident
    let t = Token start end typ in do
      ts <- tokenizeM cs'
      return (t : ts)
  where
    nameType ident
      | isKeyword        ident = return $ keywordType ident
      | isInteger        ident = return $ T_Int (read ident :: Integer)
      | isRenaming       ident = return $ T_Id (renaming ident)
      | isWellFormedName ident = return $ T_Id ident
      | otherwise              = failM LexerErrorMalformedName
                                       ("Malformed name: " ++ ident)

failM :: ErrorType -> String -> M a
failM errorType msg = do
  pos <- currentPosition
  failFS (Error errorType pos msg)

