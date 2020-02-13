module Error (
  Error(..),
  ErrorType(..),
) where

import Position(Position)

data Error = Error {
               errorType     :: ErrorType,
               errorPosition :: Position,
               errorMessage  :: String
             }
  deriving (Eq, Show)

data ErrorType =
    LexerErrorInvalidCharacter
  | LexerErrorLayout
  deriving (Eq, Show)

