{-# LANGUAGE UndecidableInstances #-}

module Juvix.Backends.Plonk.Pipeline
  ( BPlonk (..),
    compileCircuit,
  )
where

import qualified Data.Aeson as A
import Data.Field.Galois (GaloisField)
import qualified Data.HashMap.Strict as HM
import qualified Juvix.Backends.Plonk.Builder as Builder
import qualified Juvix.Backends.Plonk.Circuit as Circuit
import qualified Juvix.Backends.Plonk.Compiler as Compiler
import qualified Juvix.Backends.Plonk.Dot as Dot
import qualified Juvix.Backends.Plonk.Parameterization as Parameterization
import qualified Juvix.Backends.Plonk.Types as Types
import qualified Juvix.Core.ErasedAnn.Types as CoreErased
import qualified Juvix.Core.IR as IR
import qualified Juvix.Core.IR.TransformExt.OnlyExts as OnlyExts
import qualified Juvix.Core.IR.Typechecker.Types as TypeChecker
import Juvix.Core.Parameterisation
  ( CanApply (ApplyErrorExtra, Arg),
    TypedPrim,
  )
import qualified Juvix.Core.Parameterisation as Param
import qualified Juvix.Core.Pipeline as CorePipeline
import Juvix.Library
import qualified Juvix.Library.Feedback as Feedback
import Juvix.Pipeline as Pipeline
import Juvix.ToCore.FromFrontend as FF (CoreDefs (..))
import qualified Text.PrettyPrint.Leijen.Text as Pretty

data BPlonk f = BPlonk
  deriving (Eq, Show, Read)

instance
  ( GaloisField f,
    Eq f,
    Integral f,
    CanApply (Param.TypedPrim (Types.PrimTy f) (Types.PrimVal f)),
    CanApply (Types.PrimTy f),
    IR.HasPatSubstTerm
      (OnlyExts.T IR.NoExt)
      (Types.PrimTy f)
      (Param.TypedPrim (Types.PrimTy f) (Types.PrimVal f))
      (Types.PrimTy f),
    IR.HasWeak (Types.PrimVal f),
    IR.HasSubstValue
      IR.NoExt
      (Types.PrimTy f)
      (Param.TypedPrim (Types.PrimTy f) (Types.PrimVal f))
      (Types.PrimTy f),
    IR.HasPatSubstTerm
      (OnlyExts.T IR.NoExt)
      (Types.PrimTy f)
      (Types.PrimVal f)
      (Types.PrimTy f),
    IR.HasPatSubstTerm
      (OnlyExts.T IR.NoExt)
      (Types.PrimTy f)
      (Types.PrimVal f)
      (Types.PrimVal f),
    IR.HasPatSubstTerm
      (OnlyExts.T TypeChecker.T)
      (Types.PrimTy f)
      (TypedPrim (Types.PrimTy f) (Types.PrimVal f))
      (Types.PrimTy f),
    Show (Arg (Types.PrimTy f)),
    Show (ApplyErrorExtra (Types.PrimTy f)),
    Show
      (ApplyErrorExtra (TypedPrim (Types.PrimTy f) (Types.PrimVal f))),
    A.ToJSON (Circuit.ArithCircuit f)
  ) =>
  HasBackend (BPlonk f)
  where
  type Ty (BPlonk f) = Types.PrimTy f
  type Val (BPlonk f) = Types.PrimVal f
  stdlibs _ = ["stdlib/Circuit.ju"]
  typecheck ctx = do
    let res = Pipeline.contextToCore ctx (Parameterization.param @f)
    case res of
      Right (FF.CoreDefs _order globals) -> do
        let globalDefs = HM.mapMaybe Pipeline.toCoreDef globals
        -- TODO: Fix MAIN
        case HM.elems $ HM.filter Pipeline.isMain globalDefs of
          [] -> Feedback.fail $ "No main function found in " <> show globalDefs
          [IR.RawGFunction f]
            | IR.RawFunction _name usage ty (clause :| []) <- f,
              IR.RawFunClause _ [] term _ <- clause -> do
              let convGlobals = map (Pipeline.convGlobal Types.PField) globalDefs
                  newGlobals = HM.map (Pipeline.unsafeEvalGlobal convGlobals) convGlobals
                  lookupGlobal = IR.rawLookupFun' globalDefs
                  inlinedTerm = IR.inlineAllGlobals term lookupGlobal
              (res, _) <- liftIO $ Pipeline.exec (CorePipeline.coreToAnn @(Types.PrimTy f) @(Types.PrimVal f) @Types.CompilationError inlinedTerm (IR.globalToUsage usage) ty) (Parameterization.param @f) newGlobals
              case res of
                Right r -> do
                  pure r
                Left err -> do
                  print term
                  Feedback.fail $ show err
          somethingElse -> Feedback.fail $ show somethingElse
      Left err -> Feedback.fail $ "failed at ctxToCore\n" ++ show err

  compile out term = do
    let circuit = compileCircuit term
    liftIO $ Dot.dotWriteSVG out (Dot.arithCircuitToDot circuit)
    writeout (out <> ".pretty") $
      let pretty = toS . Pretty.displayT . Pretty.renderPretty 1 120 . Pretty.pretty
       in pretty circuit
    writeout (out <> ".json") $
      let json = show $ A.encode circuit
       in json

compileCircuit ::
  (Integral f, Show f) =>
  CoreErased.AnnTerm
    (Types.PrimTy f)
    (CoreErased.TypedPrim (Types.PrimTy f) (Types.PrimVal f)) ->
  Circuit.ArithCircuit f
compileCircuit term = Builder.execCircuitBuilder . Compiler.compileTermWithWire $ CorePipeline.toRaw term
