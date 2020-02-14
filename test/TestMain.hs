
module TestMain(runAllTests) where

import Test(runTestSuites)
import qualified TestLexer
import qualified TestParser

runAllTests :: IO ()
runAllTests = runTestSuites [
                TestLexer.tests
              , TestParser.tests
              ]

