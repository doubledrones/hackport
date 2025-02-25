-- module unused
module Fetch(downloadTarball,downloadFileVerify) where

import Prelude hiding (catch)

import Network.HTTP (ConnError(..),Request(..),simpleHTTP
                    ,Response(..),RequestMethod(..))
import Network.URI (URI,uriPath,parseURI)
import Text.Regex (Regex,mkRegex,matchRegex)
import System.GPG
import Control.Monad.Error
import System.Directory
import System.FilePath
import Data.Typeable

import Error
import Action

filenameRegex :: Regex
filenameRegex = mkRegex "^.*?/([^/]*?)"

uriToFileName :: URI -> Maybe FilePath
uriToFileName uri = maybe Nothing (\x->Just (head x)) (matchRegex filenameRegex (uriPath uri))

downloadURI :: FilePath		-- ^ a directory to store the file
            -> URI 		-- ^ the url
            -> IO FilePath	-- ^ the path of the downloaded file
downloadURI path uri = do
	fileName <- maybe (throwEx $ InvalidTarballURL (show uri) "URL doesn't contain a filename") return (uriToFileName uri)
	httpResult <- simpleHTTP request
	Response {rspCode=code,rspBody=body,rspReason=reason} <- either (\x->throwError $ DownloadFailed (show uri) "Connection failed") return httpResult
	if code==(2,0,0) then (do
		let writePath=path </> fileName
		writeFile writePath body
		return writePath) else throwEx $ DownloadFailed (show uri) ("Code "++show code++":"++reason)
	where
	request = Request
		{rqURI=uri
		,rqMethod=GET
		,rqHeaders=[]
		,rqBody=""}


downloadFileVerify ::
	FilePath ->		-- ^ the directory to store the files
	String ->		-- ^ the url of the tarball
	String ->		-- ^ the url of the signature
	IO (FilePath,FilePath)	-- ^ the tarballs and signatures path
downloadFileVerify path url sigurl = do
	tarballPath <- downloadTarball path url
	sigPath <- downloadSig path sigurl `catchEx` \e-> do
                      removeFile tarballPath
                      throwEx x
	verified <- verifyFile stdOptions tarballPath sigPath
	if verified then return (tarballPath,sigPath) else (do
		removeFile tarballPath
		removeFile sigPath
		throwEx $ VerificationFailed url sigurl)

downloadTarball ::
	FilePath ->
	String ->
	IO FilePath
downloadTarball dir url = download dir url InvalidTarballURL

downloadSig ::
	FilePath ->
	String ->
	IO FilePath
downloadSig dir url = download dir url InvalidSignatureURL

download :: FilePath				-- ^ the folder to store the file in
	 -> String				-- ^ the url
	 -> (String -> String -> HackPortError)	-- ^ a function to construct an error
	 -> IO FilePath			-- ^ the resulting file's path
download dir url errFunc = do
	parsedURL <- maybe (throwEx $ errFunc url "Parsing failed") return (parseURI url)
	downloadURI dir parsedURL
