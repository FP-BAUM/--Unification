
module TestLexer(tests) where

import Test(TestSuite(..), Test(..))

import Error(Error(..), ErrorType(..))
import Lexer.Lexer
import Lexer.Token(Token(..), TokenType(..))

test :: String -> String -> Either ErrorType [TokenType] -> Test
test description source expectedResult =
  TestCase description 
           (normalizeResult (tokenize "test" source))
           expectedResult
  where
    normalizeResult (Left  e)    = Left (errorType e)
    normalizeResult (Right toks) = Right (map tokenType toks)

testOK :: String -> String -> [TokenType] -> Test
testOK description source expectedTokens =
  test description source (Right expectedTokens)

testError :: String -> String -> ErrorType -> Test
testError description source errorType =
  test description source (Left errorType)

tests :: TestSuite
tests = TestSuite "LEXER" [

  -- Whitespace
  testOK "Ignore whitespace" " \r\n\t" [],

  -- Punctuation
  testOK "Punctuation"
         "(){};_"
         [
           T_LBrace, -- layout
           T_LParen, T_RParen, T_LBrace, T_RBrace, T_Semicolon,
           T_Underscore,
           T_RBrace  -- layout
         ],

  -- Invalid character
  testError "Reject invalid character"
            "\x00" -- NUL character
            LexerErrorInvalidCharacter,

  -- Keywords
  testOK "Keywords"
         "class data import in instance \\ let{} module where{}"
         [
           T_LBrace,
           T_Class, T_Data, T_Import, T_In, T_Instance, T_Lambda,
           T_Let, T_LBrace, T_RBrace, T_Module,
           T_Where, T_LBrace, T_RBrace,
           T_RBrace
         ],

  -- Numeric constants
  testOK "Integers"
         "0 1 42 01 010" 
         [
           T_LBrace,
           T_Int 0, T_Int 1, T_Int 42, T_Int 1, T_Int 10,
           T_RBrace
         ],

  -- Identifiers
  testOK "Identifiers"
         "if_then_else_ - - ∀|- 1a" 
         [
           T_LBrace,
           T_Id "if", T_Underscore,
           T_Id "then", T_Underscore,
           T_Id "else", T_Underscore,
           T_Id "-", T_Id "-",
           T_Id "∀|-", T_Id "1a",
           T_RBrace
         ],

  -- Comments
  testOK "Ignore single-line comments"
         "ab\nc -- this is a comment\ne(f;g)" 
         [
           T_LBrace,
           T_Id "ab",
           T_Semicolon,
           T_Id "c",
           T_Semicolon,
           T_Id "e", T_LParen, T_Id "f",
           T_Semicolon, T_Id "g", T_RParen,
           T_RBrace
         ],

  testOK "Ignore multi-line comments"
         "a {- b \n c -} d" 
         [
           T_LBrace,
           T_Id "a",
           T_Id "d",
           T_RBrace
         ],

  testOK "Ignore nested multi-line comments"
         "a {- b \n {- c -} {-{-{-c-}c{--}-}-} d -}\ne" 
         [
           T_LBrace,
           T_Id "a",
           T_Semicolon,
           T_Id "e",
           T_RBrace
         ],

  -- Layout

  testOK "Layout: explicit module"
         (unlines [
           "module Foo where",
           "a",
           "b"
         ])
         [
           T_Module,
           T_Id "Foo",
           T_Where,
           T_LBrace,
           T_Id "a",
           T_Semicolon,
           T_Id "b",
           T_RBrace
         ],

  testOK "Layout: where/let"
         (unlines [
           "a where",
           "  b",
           "  c let",
           "      d",
           "      e",
           "  f where",
           "      g",
           "      h",
           "i"
         ])
         [
           T_LBrace,
           T_Id "a",
           T_Where,
             T_LBrace,
             T_Id "b",
             T_Semicolon,
             T_Id "c",
             T_Let,
               T_LBrace,
               T_Id "d",
               T_Semicolon,
               T_Id "e",
               T_RBrace,
             T_Semicolon,
             T_Id "f",
             T_Where,
               T_LBrace,
               T_Id "g",
               T_Semicolon,
               T_Id "h",
               T_RBrace,
             T_RBrace,
           T_Semicolon,
           T_Id "i",
           T_RBrace
         ],

  testError "Layout error: unmatched '{'"
             "a {"
             LexerErrorLayout,

  testError "Layout error: unmatched '}'"
             "a }"
             LexerErrorLayout,

  -- Empty program
  testOK "Empty program"
         "" 
         []
  ]

