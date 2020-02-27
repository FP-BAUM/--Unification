module Parser.PrecedenceTable(
         PrecedenceTable,
         PrecedenceLevel,
         Associativity(..),
         Precedence,
         Operator,
         emptyPrecedenceTable,
         precedenceLevel,
         addOperator,
         precedenceTableLevels,
         precedenceTableUnion
       ) where

import qualified Data.Map as M
import qualified Data.Set as S

import Syntax.Name(QName)

data Associativity = RightAssoc | LeftAssoc | NonAssoc
  deriving (Show, Eq, Ord)

data PrecedenceTable = PT (M.Map Precedence PrecedenceLevel)
  deriving (Show, Eq)

data Operator = Op QName Associativity
  deriving (Show, Eq, Ord)

type Precedence = Integer

type PrecedenceLevel = S.Set Operator

emptyPrecedenceTable :: PrecedenceTable
emptyPrecedenceTable = PT M.empty

precedenceLevel :: Precedence -> PrecedenceTable -> PrecedenceLevel
precedenceLevel precedence (PT m) = M.findWithDefault S.empty precedence m

precedenceTableLevels :: PrecedenceTable -> [PrecedenceLevel]
precedenceTableLevels (PT m) = map snd (M.toAscList m)

precedenceTableUnion :: PrecedenceTable -> PrecedenceTable -> PrecedenceTable
precedenceTableUnion = error "NOT IMPLEMENTED"

addOperator :: Associativity -> Precedence -> QName -> PrecedenceTable
            -> PrecedenceTable
addOperator assoc precedence name t@(PT map) =
  let level = precedenceLevel precedence t
    in PT $ M.insert precedence (S.insert (Op name assoc) level) map

