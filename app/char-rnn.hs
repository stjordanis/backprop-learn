{-# LANGUAGE AllowAmbiguousTypes                      #-}
{-# LANGUAGE DataKinds                                #-}
{-# LANGUAGE FlexibleContexts                         #-}
{-# LANGUAGE GADTs                                    #-}
{-# LANGUAGE PartialTypeSignatures                    #-}
{-# LANGUAGE ScopedTypeVariables                      #-}
{-# LANGUAGE TupleSections                            #-}
{-# LANGUAGE TypeApplications                         #-}
{-# LANGUAGE TypeOperators                            #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures     #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise       #-}

import           Backprop.Learn
import           Control.DeepSeq
import           Control.Exception
import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.State
import           Data.Char
import           Data.Conduit
import           Data.Default
import           Data.Foldable
import           Data.Functor.Identity
import           Data.Primitive.MutVar
import           Data.Proxy
import           Data.Time
import           Data.Type.Equality
import           Data.Type.Tuple
import           Data.Type.Tuple
import           GHC.TypeNats
import           Numeric.LinearAlgebra.Static.Backprop
import           Numeric.LinearAlgebra.Static.Vector
import           Numeric.Opto
import           Numeric.Opto
import           Numeric.Opto.Run.Simple
import           System.Environment
import           Text.Printf
import qualified Conduit                               as C
import qualified Data.Conduit.Combinators              as C
import qualified Data.Set                              as S
import qualified Data.Text                             as T
import qualified Data.Vector.Sized                     as SV
import qualified Data.Vector.Storable.Sized            as SVS
import qualified System.Random.MWC                     as MWC
import qualified System.Random.MWC.Distributions       as MWC

-- | TODO: replace with 'LModel'
charRNN
    :: forall n h1 h2. (KnownNat n, KnownNat h1, KnownNat h2)
    => LModel _ _ (R n) (R n)
charRNN = fca softMax
       #: dropout @h2 0.25
       #: lstm
       #: dropout @h1 0.25
       #: lstm
       #: nilLM

oneHotChar
    :: KnownNat n
    => S.Set Char
    -> Char
    -> R n
oneHotChar cs = oneHotR . fromIntegral . (`S.findIndex` cs)

main :: IO ()
main = MWC.withSystemRandom @IO $ \g -> do
    sourceFile:_  <- getArgs
    charMap <- S.fromList <$> readFile sourceFile
    SomeNat (Proxy :: Proxy n) <- pure $ someNatVal (fromIntegral (length charMap))
    SomeNat (Proxy :: Proxy n') <- pure $ someNatVal (fromIntegral (length charMap - 1))
    Just Refl <- pure $ sameNat (Proxy @(n' + 1)) (Proxy @n)

    printf "%d characters found.\n" (natVal (Proxy @n))

    let model0 = charRNN @n @100 @50
        model  = trainState . unrollFinal @(SV.Vector 15) $ model0

    p0 <- initParamNormal model 0.2 g

    let report n b = do
          liftIO $ printf "(Batch %d)\n" (b :: Int)
          t0 <- liftIO getCurrentTime
          C.drop (n - 1)
          mp <- mapM (liftIO . evaluate . force) =<< await
          t1 <- liftIO getCurrentTime
          case mp of
            Nothing -> liftIO $ putStrLn "Done!"
            Just p@(p' :# s') -> do
              chnk <- lift . state $ (,[])
              liftIO $ do
                printf "Trained on %d points in %s.\n"
                  (length chnk)
                  (show (t1 `diffUTCTime` t0))
                let trainScore = testModelAll maxIxTest model (PJustI p) chnk
                printf "Training error:   %.3f%%\n" ((1 - trainScore) * 100)

                forM_ (take 15 chnk) $ \(x,y) -> do
                  let primed = primeModel model0 (PJustI p') x (PJustI s')
                  testOut <- fmap reverse . flip execStateT [] $
                      iterateModelM ( fmap (oneHotR . fromIntegral)
                                    . (>>= \r -> r <$ modify (r:))    -- trace
                                    . (`MWC.categorical` g)
                                    . SVS.fromSized
                                    . rVec
                                    )
                            100 model0 (PJustI p') y primed
                  printf "%s|%s\n"
                    (sanitize . (`S.elemAt` charMap) . fromIntegral . maxIndexR <$> (toList x ++ [y]))
                    (sanitize . (`S.elemAt` charMap) <$> testOut)
              report n (b + 1)

    C.runResourceT . flip evalStateT []
        . runConduit
        $ forever ( C.sourceFile sourceFile
                 .| C.decodeUtf8
                 .| C.concatMap T.unpack
                 .| C.map (oneHotChar charMap)
                 .| leadings
                  )
       .| skipSampling 0.02 g
       .| C.iterM (modify . (:))
       .| optoConduit
            def
            p0
            (adam def (modelGradStoch crossEntropy noReg model g))
       .| report 2500 0
       .| C.sinkNull


    -- simpleRunner
    --     def
    --     train
    --     SOSingle
    --     def
    --     model0
    --     adam
    --     g

    -- let report n b = do
    --       liftIO $ printf "(Batch %d)\n" (b :: Int)
    --       t0 <- liftIO getCurrentTime
    --       C.drop (n - 1)
    --       mp <- mapM (liftIO . evaluate . force) =<< await
    --       t1 <- liftIO getCurrentTime
    --       case mp of
    --         Nothing -> liftIO $ putStrLn "Done!"
    --         Just p@(p' :# s') -> do
    --           chnk <- lift . state $ (,[])
    --           liftIO $ do
    --             printf "Trained on %d points in %s.\n"
    --               (length chnk)
    --               (show (t1 `diffUTCTime` t0))
    --             let trainScore = testModelAll maxIxTest model (PJust p) chnk
    --             printf "Training error:   %.3f%%\n" ((1 - trainScore) * 100)

    --             forM_ (take 15 chnk) $ \(x,y) -> do
    --               let primed = primeModel model0 (PJust p') x (PJust s')
    --               testOut <- fmap reverse . flip execStateT [] $
    --                   iterateModelM ( fmap (oneHotR . fromIntegral)
    --                                 . (>>= \r -> r <$ modify (r:))    -- trace
    --                                 . (`MWC.categorical` g)
    --                                 . SVS.fromSized
    --                                 . rVec
    --                                 )
    --                         100 model0 (PJust p') y primed
    --               printf "%s|%s\n"
    --                 (sanitize . (`S.elemAt` charMap) . fromIntegral . maxIndexR <$> (toList x ++ [y]))
    --                 (sanitize . (`S.elemAt` charMap) <$> testOut)
    --           report n (b + 1)

    -- C.runResourceT . flip evalStateT []
    --     . runConduit
    --     $ forever ( C.sourceFile sourceFile
    --              .| C.decodeUtf8
    --              .| C.concatMap T.unpack
    --              .| C.map (oneHotChar charMap)
    --              .| leadings
    --               )
    --    .| skipSampling 0.02 g
    --    .| C.iterM (modify . (:))
    --    .| runOptoConduit_
    --         (RO' Nothing Nothing)
    --         p0
    --         (adam @_ @(MutVar _ _) def
    --            (modelGradStoch crossEntropy noReg model g)
    --         )
    --    .| report 2500 0
    --    .| C.sinkNull

sanitize :: Char -> Char
sanitize c | isPrint c = c
           | otherwise = '#'
