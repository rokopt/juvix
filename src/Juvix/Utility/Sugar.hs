module Juvix.Utility.Sugar where

import           Protolude

(|<<) ∷ ∀ a b f . (Functor f) ⇒ (a → b) → f a → f b
(|<<) = fmap

(>>|) ∷ ∀ a b f . (Functor f) ⇒ f a → (a → b) → f b
(>>|) = flip fmap

throw ∷ ∀ a e m . (MonadError e m) ⇒ e → m a
throw = throwError

catch ∷ ∀ a e m . (MonadError e m) ⇒ m a → (e → m a) → m a
catch = catchError