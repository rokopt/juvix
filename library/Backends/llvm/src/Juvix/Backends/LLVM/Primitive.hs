-- | Representation of LLVM primitives in Juvix.
module Juvix.Backends.LLVM.Primitive
  ( RawPrimVal (..),
    PrimVal,
    arityRaw,
  )
where

import qualified Juvix.Core.Application as App
import qualified Juvix.Core.Parameterisation as Param
import Juvix.Library

-- | TODO: Just a placeholder for now.
data PrimTy

-- | Raw representation of some primitives of LLVM.
data RawPrimVal
  = Add
  | Sub

-- | The primitive values as exposed to users of Juvix, wrapping inside a
-- return or a continuation.
type PrimVal ext = App.Return' ext (Param.PrimType PrimTy) RawPrimVal

-- | Arity of `RawPrimVal`.
arityRaw :: RawPrimVal -> Natural
arityRaw Add = 2
arityRaw Sub = 2