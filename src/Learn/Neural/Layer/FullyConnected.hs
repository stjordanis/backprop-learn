{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE InstanceSigs              #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE PolyKinds                 #-}
{-# LANGUAGE StandaloneDeriving        #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeInType                #-}

module Learn.Neural.Layer.FullyConnected (
) where

import           Data.Kind
import           Data.Singletons.TypeLits
import           GHC.Generics                   (Generic)
import           Learn.Neural.Layer
import           Numeric.BLAS
import           Numeric.Backprop
import           Numeric.Tensor
import           Statistics.Distribution
import           Statistics.Distribution.Normal
import qualified Generics.SOP                   as SOP

data FCLayer :: Type

instance Num (CParam FCLayer b ('BV i) ('BV o))

deriving instance Generic (CParam FCLayer b ('BV i) ('BV o))
instance SOP.Generic (CParam FCLayer b ('BV i) ('BV o))

instance (KnownNat i, KnownNat o) => Component FCLayer ('BV i) ('BV o) where
    data CParam  FCLayer b ('BV i) ('BV o) =
            FCP { fcWeights :: !(b ('BM o i))
                , fcBiases  :: !(b ('BV o))
                }
    type CState  FCLayer b ('BV i) ('BV o) = 'Nothing
    type CConstr FCLayer b ('BV i) ('BV o) = Num (b ('BM o i))
    data CConf   FCLayer   ('BV i) ('BV o) = forall d. ContGen d => FCC d

    componentOp = bpOp . withInps $ \(x :< p :< Ø) -> do
        w :< b :< Ø <- gTuple #<~ p
        y <- matVecOp ~$ (w :< x :< Ø)
        z <- (+.)     ~$ (y :< b :< Ø)
        return $ only z

    initComponent = \case
      SBV i -> \case
        so@(SBV o) -> \case
          FCC d -> \g -> do
            w <- genA (SBM o i) $ \_ ->
              realToFrac <$> genContVar d g
            b <- genA so $ \_ ->
              realToFrac <$> genContVar d g
            return . only_ $ FCP w b

    defConf = FCC (normalDistr 0 0.5)

instance (KnownNat i, KnownNat o) => DefLayerConf FCLayer r b ('BV i) ('BV o) where
    defLayerConf = defLCPure
