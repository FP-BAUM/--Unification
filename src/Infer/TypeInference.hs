module Infer.TypeInference(inferTypes) where

import qualified Data.Set as S
import qualified Data.Map as M
import Data.List(union)
import Data.Maybe(fromJust)

import FailState(FailState, getFS, putFS, modifyFS, evalFS, failFS, logFS)
import Error(Error(..), ErrorType(..))
import Position(Position(..), unknownPosition)
import Syntax.Name(QName(..), operatorArrow, primitiveInt)
import Syntax.AST(
         AnnProgram(..), Program,
         AnnDeclaration(..), Declaration,
         AnnSignature(..), Signature,
         AnnEquation(..), Equation,
         AnnConstraint(..), Constraint,
         AnnCaseBranch(..), CaseBranch,
         AnnExpr(..), Expr, exprHeadVariable, exprFreeVariables
       )
import Calculus.Types(
         TypeMetavariable, TypeConstraint(..),
         TypeScheme(..),  ConstrainedType(..), Type(..),
         substituteConstrainedType,
         constrainedTypeFreeVariables,
         tFun, tInt
       )

inferTypes :: Program -> Either Error Program
inferTypes program = evalFS (inferTypeProgramM program) initialState
  where initialState = TypeInferState {
                         statePosition      = unknownPosition
                       , stateNextFresh     = 0
                       , stateTypeConstants = S.empty
                       , stateEnvironment   = [M.empty]
                       , stateSubstitution  = M.empty
                       }

---- Type inference monad

data TypeInferState =
     TypeInferState {
       statePosition      :: Position
     , stateNextFresh     :: Integer
     , stateTypeConstants :: S.Set QName
                                  -- Type constructors and type synonyms
     , stateEnvironment   :: [M.Map QName TypeScheme]
                                  -- Non-empty stack of ribs
     , stateSubstitution :: M.Map TypeMetavariable Type 
     }

type M = FailState TypeInferState

failM :: ErrorType -> String -> M a
failM errorType msg = do
  pos <- currentPosition
  failFS (Error errorType pos msg)

setPosition :: Position -> M ()
setPosition pos = modifyFS (\ state -> state { statePosition = pos })

currentPosition :: M Position
currentPosition = do
  state <- getFS
  return $ statePosition state

freshType :: M Type
freshType = do
  state <- getFS
  putFS (state { stateNextFresh = stateNextFresh state + 1 })
  return $ TMetavar (stateNextFresh state)

bindType :: QName -> TypeScheme -> M ()
bindType varName typ = do
  state <- getFS
  let (rib : ribs) = stateEnvironment state in
   if M.member varName rib
    then failM TypeErrorVariableAlreadyDeclared
               ("Variable \"" ++ show varName ++ "\" already declared.")
    else putFS (state { stateEnvironment = M.insert varName typ rib : ribs })

setRepresentative :: TypeMetavariable -> Type -> M ()
setRepresentative x typ = do
  state <- getFS
  putFS (state {
           stateSubstitution = M.insert x typ (stateSubstitution state)
         })

bindToFreshType :: QName -> M ()
bindToFreshType x = do
  typ <- freshType
  bindType x (TypeScheme [] (ConstrainedType [] typ))

bindToFreshTypeIfNotLocallyBound :: QName -> M ()
bindToFreshTypeIfNotLocallyBound x = do
  state <- getFS
  if M.member x (head (stateEnvironment state))
   then return ()
   else bindToFreshType x

lookupType :: QName -> M TypeScheme
lookupType x = do
    state <- getFS
    rec (stateEnvironment state)
  where
    rec []           =
      failM TypeErrorUnboundVariable
            ("Unbound variable \"" ++ show x ++ "\"")
    rec (rib : ribs) =
      if M.member x rib
       then return $ M.findWithDefault undefined x rib
       else rec ribs

getAllBoundVars :: M (S.Set QName)
getAllBoundVars = do
  state <- getFS
  return $ S.unions (map M.keysSet (stateEnvironment state))

enterScopeM :: M ()
enterScopeM = modifyFS (\ state -> state {
                stateEnvironment = M.empty : stateEnvironment state
              })

exitScopeM :: M ()
exitScopeM = modifyFS (\ state -> state {
               stateEnvironment = tail (stateEnvironment state)
             })

allTypeConstants :: M (S.Set QName)
allTypeConstants = do
  state <- getFS
  return $ stateTypeConstants state

addTypeConstant :: QName -> M ()
addTypeConstant name =  modifyFS (\ state ->
    state { stateTypeConstants = S.insert name (stateTypeConstants state) }
  )

freshenVariables :: [QName] -> ConstrainedType -> M ConstrainedType
freshenVariables names constrainedType = do
  sub <- M.fromList <$> mapM (\ name -> do ft <- freshType 
                                           return (name, ft)) names
  return $ substituteConstrainedType sub constrainedType

lookupMetavar :: TypeMetavariable -> M (Maybe Type)
lookupMetavar meta = do
  state <- getFS
  return $ M.lookup meta (stateSubstitution state)

---- Type inference algorithm

inferTypeProgramM :: Program -> M Program
inferTypeProgramM (Program decls) = do
  -- Declare built-in type constructors
  addTypeConstant operatorArrow
  addTypeConstant primitiveInt
  -- Infer
  mapM_ collectTypeDeclarationM decls
  mapM_ collectSignaturesM decls
  decls' <- inferTypeDeclarationsM decls
  return $ Program decls

collectTypeDeclarationM :: Declaration -> M ()
collectTypeDeclarationM (TypeDeclaration pos typ value) = do
  case exprHeadVariable typ of
    Just name -> addTypeConstant name
    _ -> error "Type has no head variable"
  error "NOT FULLY IMPLEMENTED -- TODO: RECORD TYPE SYNONYM DECLARATION"
collectTypeDeclarationM (DataDeclaration _ typ _) = do
  case exprHeadVariable typ of
    Just name -> addTypeConstant name
    _ -> error "Type has no head variable"
collectTypeDeclarationM _ = return ()

collectSignaturesM :: Declaration -> M ()
collectSignaturesM (DataDeclaration pos typ constructors) = do
  mapM_ collectSignatureM constructors
collectSignaturesM (TypeSignature signature) = collectSignatureM signature
collectSignaturesM _ = return ()

inferTypeDeclarationsM :: [Declaration] -> M [Declaration]
inferTypeDeclarationsM decls =
    let definedVars = S.unions (map declVars decls)
     in do mapM_ bindToFreshTypeIfNotLocallyBound (S.toList definedVars)
           mapM inferTypeDeclarationM decls
  where
    declVars (ValueDeclaration (Equation _ lhs _)) =
      S.fromList [fromJust (exprHeadVariable lhs)]
    declVars _ = S.empty

inferTypeDeclarationM :: Declaration -> M Declaration
inferTypeDeclarationM decl@(DataDeclaration _ _ _) =
  -- TODO: transform constraints in constructor signatures
  return decl
inferTypeDeclarationM (TypeDeclaration pos typ value) =
  error "NOT IMPLEMENTED"
inferTypeDeclarationM (ValueDeclaration equation) = do
  equation' <- inferTypeEquationM equation
  return $ ValueDeclaration equation'
inferTypeDeclarationM decl@(TypeSignature _) = 
  -- TODO: transform constraints in signature
  return decl
inferTypeDeclarationM (ClassDeclaration pos className typeName methods) =
  error "NOT IMPLEMENTED"
inferTypeDeclarationM (InstanceDeclaration pos className typ
                                               constraints methods) =
  error "NOT IMPLEMENTED"

collectSignatureM :: Signature -> M ()
collectSignatureM (Signature pos name typ constraints) = do 
  setPosition pos
  ct <- constrainedType constraints typ
  cs <- allTypeConstants
  let fvariables = S.toList $ constrainedTypeFreeVariables ct S.\\ cs
  bindType name (TypeScheme fvariables ct)

constrainedType :: [Constraint] -> Expr -> M ConstrainedType
constrainedType constraints expr =
    return $ ConstrainedType cts typ
  where
    typ = exprToType expr
    cts = map constraintToTypeConstraint constraints

inferTypeEquationM :: Equation -> M Equation
inferTypeEquationM (Equation pos lhs rhs) = do
  setPosition pos
  bound <- getAllBoundVars
  let lhsFree = exprFreeVariables bound lhs
      --rhsFree = exprFreeVariables (bound `S.union` lhsFree) rhs
      --allFree = lhsFree `S.union` rhsFree
   in do
     -- TODO: transform constraints
     enterScopeM
     mapM_ bindToFreshType lhsFree
     (ConstrainedType tcsl tl, lhs') <- inferTypeExprM lhs
     (ConstrainedType tcsr tr, rhs') <- inferTypeExprM rhs
     unifyTypes tl tr (union tcsl tcsr)
     exitScopeM
     return $ Equation pos lhs' rhs'

representative :: Type -> M Type
representative (TMetavar x) = do
  mt <- lookupMetavar x
  case mt of
    Just t  -> representative t
    Nothing -> return (TMetavar x)
representative t            = return t

unfoldType :: Type -> M Type
unfoldType t = do
  t' <- representative t
  case t' of
    TApp t1 t2 -> do
      t1' <- unfoldType t1
      t2' <- unfoldType t2
      return $ TApp t1' t2'
    _          -> return t'

occursIn :: TypeMetavariable -> Type -> M Bool
occursIn x t = do
  t' <- representative t
  case t' of
    TMetavar y -> return (x == y)
    TVar _     -> return False
    TApp t1 t2 -> do
      b1 <- occursIn x t1
      b2 <- occursIn x t2
      return (b1 || b2)

unifyTypes :: Type -> Type -> [TypeConstraint] -> M [TypeConstraint]
unifyTypes t1 t2 cs = do
  unify t1 t2
  -- TODO: Solve contraints
  return cs
  where
    unify :: Type -> Type -> M ()
    unify t1 t2 = do
      t1' <- representative t1
      t2' <- representative t2
      case (t1', t2') of
        (TMetavar x, TMetavar y) | x == y -> return ()
        (TMetavar x, t) -> do
          b <- x `occursIn` t
          if b
           then unifFailOccursCheck t1 t2
           else setRepresentative x t
        (t, TMetavar x) -> unify (TMetavar x) t
        (TVar a, TVar b) | a == b -> return ()
        (TApp t11 t12, TApp t21 t22) -> do unify t11 t21
                                           unify t12 t22
        _ -> unifFailClash t1 t2
    --
    unifFailOccursCheck = unifFail TypeErrorUnificationOccursCheck
    unifFailClash       = unifFail TypeErrorUnificationClash
    unifFail errorType t1 t2 = do
      t1' <- unfoldType t1
      t2' <- unfoldType t2
      failM errorType
            ("Types do not unify (" ++ show errorType ++ "):\n" ++
             "  " ++ show t1' ++ "\n" ++
             "  " ++ show t2')

inferTypeExprM :: Expr -> M (ConstrainedType, Expr)
inferTypeExprM (EInt pos i) = return (ConstrainedType [] tInt, EInt pos i)
-- x
inferTypeExprM (EVar pos x) = do
  setPosition pos
  TypeScheme gvars constrainedType <- lookupType x
  constrainedType' <- freshenVariables gvars constrainedType -- Instantiate
  return (constrainedType', EVar pos x)
-- e1 e2
inferTypeExprM (EApp pos e1 e2) = do
  setPosition pos
  (ConstrainedType tcs1 t1, e1') <- inferTypeExprM e1
  (ConstrainedType tcs2 t2, e2') <- inferTypeExprM e2
  tr <- freshType
  tcs <- unifyTypes t1
                    (tFun t2 tr)
                    (union tcs1 tcs2)
  return (ConstrainedType tcs tr, (EApp pos e1' e2'))
-- \ e1 -> e2
inferTypeExprM (ELambda pos e1 e2) = do
  setPosition pos
  bound <- getAllBoundVars
  let freeParamVars = exprFreeVariables bound e1

   in do
    enterScopeM
    mapM_ bindToFreshType freeParamVars
    (ConstrainedType ce1 te1, e1') <- inferTypeExprM e1
    (ConstrainedType ce2 te2, e2') <- inferTypeExprM e2
    exitScopeM
    return $ (ConstrainedType (union ce1 ce2) (tFun te1 te2), ELambda pos e1' e2')
-- let e1 = b1 ei = ...decls'
-- in ...body
inferTypeExprM (ELet pos decls body) = do
  setPosition pos
  bound <- getAllBoundVars
  enterScopeM
  mapM_ collectSignaturesM decls
  decls' <- inferTypeDeclarationsM decls
  -- TODO: generalize signature types
  (typeScheme, body') <- inferTypeExprM body
  exitScopeM
  return (typeScheme, ELet pos decls' body')
-- case a of b
inferTypeExprM (ECase pos e1 cases) = error "NOT IMPLEMENTED"
-- fresh x in a
inferTypeExprM (EFresh pos x body) = do
  enterScopeM
  bindToFreshType x
  (schema, body') <- inferTypeExprM body
  exitScopeM
  return (schema, EFresh pos x body')

exprToType :: Expr -> Type
exprToType (EVar _ x)     = TVar x
exprToType (EApp _ t1 t2) = TApp (exprToType t1) (exprToType t2)
exprToType _              = error "(Malformed type)"

constraintToTypeConstraint :: Constraint -> TypeConstraint
constraintToTypeConstraint (Constraint _ className typeName) =
  TypeConstraint className (TVar typeName)
