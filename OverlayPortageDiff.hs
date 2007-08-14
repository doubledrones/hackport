module OverlayPortageDiff where
--module OverlayPortageDiff where

import Action
import AnsiColor
import Bash
import Config
import Diff
import Portage
import P2

import Control.Arrow
import Control.Monad.Error
import Control.Monad.State

import qualified Data.List as List
import Data.Version
import Distribution.Package

import qualified Data.ByteString.Lazy.Char8 as L

import Data.Char
import qualified Data.Map as Map
import qualified Data.Set as Set

import qualified Data.Traversable as T

data Diff a = D
    { sameSame :: [a] -- ^ file exists in both portdirs, and are identical
    , fileDiffers :: [a] -- ^ file exists in both portdirs, but are different
    , only1 :: [a] -- ^ only exist in the first dir
    , only2 :: [a] -- ^ only exist in the second dir
    }

overlayonly :: HPAction ()
overlayonly = do
    cfg <- getCfg
    portdir <- getPortDir
    overlayPath <- getOverlayPath
    portage <- liftIO $ readPortageTree portdir
    overlay <- liftIO $ readPortageTree overlayPath
    info "These packages are in the overlay but not in the portage tree:"
    let (over, both) = portageDiff overlay portage

    both' <- T.forM both $ mapM $ \e -> liftIO $ do
            -- can't fail, we know the ebuild exists in both portagedirs
            let (Just e1) = lookupEbuildWith portage (ePackage e) (comparing eVersion e)
                (Just e2) = lookupEbuildWith overlay (ePackage e) (comparing eVersion e)
            eq <- equals (eFilePath e1) (eFilePath e2)
            return (let ev = eVersion e in (ev, toColor (if eq then Green else Yellow) (show ev)))

    let over' = Map.map (map ((id &&& (toColor Red . show)).eVersion)) over

        meld = Map.map (map snd) $ Map.unionWith (\a b -> List.sort (a++b)) both' over'

    forM_ (Map.toAscList meld) $ \(package, versions) -> liftIO $ do
        print package
        forM_ versions putStrLn

toColor c t = inColor c False Default t

-- incomplete
portageDiff :: Portage -> Portage -> (Portage, Portage)
portageDiff p1 p2 = (in1, ins)
    where ins = Map.filter (not . null) $
                    Map.intersectionWith (List.intersectBy $ comparing eVersion) p1 p2
          in1 = Map.filter (not . null) $
                    Map.differenceWith (\xs ys ->
                        let lst = filter (\x -> any (\y -> eVersion x == eVersion y) ys) xs in
                        if null lst
                            then Nothing
                            else Just lst
                            ) p1 p2

comparing f x y = f x == f y


-- | Compares two ebuilds, returns True if they are equal.
--   Disregards comments.
equals :: FilePath -> FilePath -> IO Bool
equals fp1 fp2 = do
    f1 <- L.readFile fp1
    f2 <- L.readFile fp2
    return (equal' f1 f2)

equal' :: L.ByteString -> L.ByteString -> Bool
equal' = comparing essence
    where
    essence = filter (not . isEmpty) . filter (not . isComment) . L.lines
    isComment = L.isPrefixOf (L.pack "#") . L.dropWhile isSpace
    isEmpty = L.null . L.dropWhile isSpace

