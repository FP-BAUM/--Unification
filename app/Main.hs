module Main where

import System.IO(hPutStrLn, stderr)
import System.Environment(getArgs)

import Error(Error(..))
import Position(positionRegion)
import Lexer.Lexer(tokenize)
import Parser.Reader(readSource)
import Parser.Parser(parse)
import Infer.KindInference(inferKinds)
import Infer.TypeInference(inferTypes)
import Desugaring.Desugaring(desugarProgram)

import TestMain(runAllTests)

main :: IO ()
main = do
  args <- getArgs
  run args

run :: [String] -> IO ()
run ["-T"]        = runAllTests
run ["-t", input] = runTokenizer input
run ["-r", input] = runReader input
run ["-p", input] = runParser input
run ["-k", input] = runKindInference input
run ["-i", input] = runTypeInference input
run ["-d", input] = runDesugaring input
run _             = usage

runTokenizer :: String -> IO ()
runTokenizer filename = do
  source <- readFile filename
  case tokenize filename source of
    Left  e      -> die e
    Right tokens -> mapM_ (putStrLn . show) tokens

runReader :: String -> IO ()
runReader filename = do
  res <- readSource filename
  case res of
    Left  e      -> die e
    Right tokens -> mapM_ (putStrLn . show) tokens

runParser :: String -> IO ()
runParser filename = do
  res <- readSource filename
  case res of
    Left  e      -> die e
    Right tokens -> do
      case parse tokens of
        Left e        -> die e
        Right program -> putStrLn (show program)

runKindInference :: String -> IO ()
runKindInference filename = do
  res <- readSource filename
  case res of
    Left  e      -> die e
    Right tokens -> do
      case parse tokens of
        Left e        -> die e
        Right program -> do
          case inferKinds program of
            Left e    -> die e
            Right ()  -> putStrLn "OK"

runTypeInference :: String -> IO ()
runTypeInference filename = do
  res <- readSource filename
  case res of
    Left  e      -> die e
    Right tokens -> do
      case parse tokens of
        Left e        -> die e
        Right program -> do
          case inferKinds program of
            Left e    -> die e
            Right () -> do
              case inferTypes program of
                Left e -> die e
                Right program' -> putStrLn (show program')

runDesugaring :: String -> IO ()
runDesugaring filename = do
  res <- readSource filename
  case res of
    Left  e      -> die e
    Right tokens -> do
      case parse tokens of
        Left e        -> die e
        Right program -> do
          case inferKinds program of
            Left e    -> die e
            Right () -> do
              case inferTypes program of
                Left e -> die e
                Right program' -> do
                  case desugarProgram program' of
                    Left e -> die e
                    Right termC -> putStrLn (show termC)

usage :: IO ()
usage = do
  putStrLn "Usage:"
  putStrLn "  la -T              Run tests."
  putStrLn "  la -t foo.la       Tokenize file."
  putStrLn "  la -r foo.la       Tokenize file (including dependencies)."
  putStrLn "  la -p foo.la       Parse file."
  putStrLn "  la -k foo.la       Infer kinds."
  putStrLn "  la -i foo.la       Infer types."
  putStrLn "  la -d foo.la       Desugar program."

die :: Error -> IO ()
die e = do
  hPutStrLn stderr ("---ERROR---")
  hPutStrLn stderr (positionRegion (errorPosition e))
  hPutStrLn stderr "---"
  hPutStrLn stderr (errorMessage e)

