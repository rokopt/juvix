module Juvix.Core.IR.Typechecker.Env where

import Juvix.Library
import Juvix.Core.IR.Typechecker.Types
import Juvix.Core.IR.Typechecker.Log


data EnvCtx primTy primVal
  = EnvCtx {typecheckerLog :: [Log primTy primVal]}
  deriving (Show, Eq, Generic)

type EnvAlias primTy primVal =
  ExceptT (TypecheckError primTy primVal)
    (State (EnvCtx primTy primVal))

newtype EnvTypecheck primTy primVal a = EnvTyp (EnvAlias primTy primVal a)
  deriving (Functor, Applicative, Monad)
  deriving (HasThrow "typecheckError" (TypecheckError primTy primVal)) via
    MonadError
      (ExceptT (TypecheckError primTy primVal)
        (MonadState (State (EnvCtx primTy primVal))))
  deriving
    (HasSink "typecheckerLog" [Log primTy primVal],
     HasWriter "typecheckerLog" [Log primTy primVal])
  via
    WriterLog
      (Field "typecheckerLog" ()
        (MonadState
          (ExceptT (TypecheckError primTy primVal)
            (State (EnvCtx primTy primVal)))))

exec :: EnvTypecheck primTy primVal a
     -> (Either (TypecheckError primTy primVal) a, EnvCtx primTy primVal)
exec (EnvTyp env) = runState (runExceptT env) (EnvCtx [])