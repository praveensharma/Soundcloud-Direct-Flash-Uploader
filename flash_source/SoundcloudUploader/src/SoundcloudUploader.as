package
{
	import com.dasflash.soundcloud.as3api.SoundcloudClient;
	import com.dasflash.soundcloud.as3api.SoundcloudDelegate;
	import com.dasflash.soundcloud.as3api.SoundcloudResponseFormat;
	import com.dasflash.soundcloud.as3api.events.SoundcloudEvent;
	import com.dasflash.soundcloud.as3api.events.SoundcloudFaultEvent;
	
	import flash.display.Loader;
	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.MouseEvent;
	import flash.events.ProgressEvent;
	import flash.events.TimerEvent;
	import flash.external.ExternalInterface;
	import flash.net.FileReference;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.utils.Timer;
	
	import org.iotashan.oauth.OAuthToken;
	import org.osmf.net.StreamingURLResource;

	public class SoundcloudUploader extends Sprite
	{	
		private var consumerKey:String = "";
		private var consumerSecret:String = "";
		
		private var parameterString:String = root.loaderInfo.parameters.params;
		private var parameters:Object = new Object();
		
		private var tokenKey:String = "";
		private var tokenSecret:String = "";
		
		private var trackTitle:String = "";
		private var trackDescription:String = "";
		private var trackSharing:String = "public";
		private var trackDownloadable:Boolean = true;
		private var buttonURL:String = "";
		
		// setup timer to check for data response
		private var dataTimer:Timer = new Timer(4000);
			
		// reference to soundcloud client
		protected var scClient:SoundcloudClient;
		
		// reference to uploaded file
		private var track:FileReference;
		private var fileReference:FileItem;
		
		// temporary test button
		private var button:Sprite = new Sprite();
		
		public function SoundcloudUploader():void
		{
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
			
			parameters = loadPostParams(parameterString);
			
			loadFlashVars();			
			loadButton();
			
			// create OAuthToken
			var accessToken:OAuthToken = new OAuthToken(tokenKey, tokenSecret);
			
			// create soundcloud client			
			scClient = new SoundcloudClient(consumerKey, consumerSecret, accessToken, false, SoundcloudResponseFormat.XML);		
			
			getMe();
		}
		
		private function loadFlashVars():void
		{
			consumerKey = parameters.consumerKey;
			consumerSecret = parameters.consumerSecret;
			
			tokenKey = parameters.tokenKey;
			tokenSecret = parameters.tokenSecret; 
			
			trackTitle = parameters.trackTitle;
			trackDescription = parameters.trackDescription;
			trackSharing = parameters.trackSharing;
			trackDownloadable = parameters.trackDownloadable;
			
			buttonURL = parameters.buttonURL;
		}
		
		private function loadButton():void
		{
			var buttonLoader:Loader = new Loader();
			buttonLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, doNothing );
			buttonLoader.contentLoaderInfo.addEventListener(HTTPStatusEvent.HTTP_STATUS, doNothing );
			buttonLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, imageLoaded);
			
			buttonLoader.load(new URLRequest(buttonURL));
		}
		
		private function imageLoaded(event:Event):void
		{			
			button.buttonMode = true;
			button.mouseChildren = false;
			button.addChild(event.currentTarget.content);
			button.addEventListener(MouseEvent.CLICK, selectTrackButtonHandler);
			
			addChild(button)
		}
		
		/* GET USER INFO */
		protected function getMe():void
		{
			var delegate:SoundcloudDelegate = scClient.sendRequest("me", URLRequestMethod.GET);
			delegate.addEventListener(SoundcloudEvent.REQUEST_COMPLETE, getMeCompleteHandler);
			
			trace("requesting user data");
		}
		
		private function getMeCompleteHandler(event:SoundcloudEvent):void
		{
			trace(event.data);
			
			button.visible = true;
		}
		
		/* SELECT FILE */
		protected function selectTrackButtonHandler(event:MouseEvent):void
		{			
			var fileReference:FileReference = new FileReference();
				fileReference.addEventListener(Event.SELECT, fileSelectHandler);
				fileReference.browse();
			
			trace("selecting file");
		}
		
		/* UPLOAD FILE */
		protected function fileSelectHandler(event:Event):void
		{
			track = FileReference(event.target);
			
			fileReference = new FileItem(track, parameters.movieName, 0); 				
				
			var params:Object = {};
				params["track[title]"] = trackTitle;
				params["track[asset_data]"] = track;
				params["track[description]"] = trackDescription;
				params["track[downloadable]"] = trackDownloadable;
				params["track[sharing]"] = trackSharing;
			
			// create service call delegate
			var delegate:SoundcloudDelegate = scClient.sendRequest("tracks", URLRequestMethod.POST, params);			
				delegate.addEventListener("queryAccount", queryAccount);
				delegate.addEventListener(ProgressEvent.PROGRESS, onUploadProgress);
				delegate.addEventListener(SoundcloudFaultEvent.FAULT, faultHandler);
				delegate.addEventListener(SoundcloudEvent.REQUEST_COMPLETE, uploadCompleteHandler);
			
			trace("upload started");
			
			// if testing with files < 1MB uncomment
			//queryAccount(null);
		}
		
		private function queryAccount(event:Event):void
		{
			dataTimer.addEventListener(TimerEvent.TIMER, timerComplete);
			dataTimer.start();
		}
		
		private function timerComplete(event:TimerEvent):void
		{
			dataTimer.removeEventListener(TimerEvent.TIMER, timerComplete);
			dataTimer.stop();
			
			trace("Weeee");
			
			var delegate:SoundcloudDelegate = scClient.sendRequest("me/tracks", URLRequestMethod.GET);				
				delegate.addEventListener(SoundcloudFaultEvent.FAULT, faultHandler);
				delegate.addEventListener(SoundcloudEvent.REQUEST_COMPLETE, uploadCompleteHandler);
				delegate.addEventListener(Event.COMPLETE, uploadCompleteHandler);
		}	
		
		private function onUploadProgress(event:ProgressEvent):void
		{
			// On early than Mac OS X 10.3 bytesLoaded is always -1, convert this to zero. Do bytesTotal for good measure.
			//  http://livedocs.adobe.com/flex/3/langref/flash/net/FileReference.html#event:progress
			var bytesLoaded:Number = event.bytesLoaded < 0 ? 0 : event.bytesLoaded;
			var bytesTotal:Number = event.bytesTotal < 0 ? 0 : event.bytesTotal;
			
			ExternalCall.UploadProgress("uploadProgress", fileReference.ToJavaScriptObject(), bytesLoaded, bytesTotal);
		}
		
		protected function uploadCompleteHandler(event:SoundcloudEvent):void
		{
			var tmpTrackXML:XML = XML(event.data);
			var uploadedTrack:XMLList = tmpTrackXML..track.(title == trackTitle);
			
			var soundcloudID:String = uploadedTrack.child("id").text();
			var streamURL:String = uploadedTrack.child("stream-url").text();
			var downloadURL:String = uploadedTrack.child("download-url").text();
			
			trace(uploadedTrack);
			trace("id: " + soundcloudID);
			trace("stream url: " + streamURL);
			trace("download url: " + downloadURL);						
			
			ExternalCall.UploadComplete("scSWFUploader.uploadComplete", fileReference.ToJavaScriptObject(), streamURL, downloadURL, soundcloudID);
			
			trace("upload complete");
		}
		
		protected function faultHandler(event:SoundcloudFaultEvent):void
		{
			trace("error: " + event.message);
		}
		
		private function doNothing(event:Event):void
		{
			return;
		}
		
		private function SetupExternalInterface():void {
			try 
			{
				//ExternalInterface.addCallback("StartUpload", getMe);
				//ExternalInterface.addCallback("StopUpload", stopUpload);
				//ExternalInterface.addCallback("CancelUpload", cancelUpload);
				
				//ExternalInterface.addCallback("SetButtonImageURL", loadButton);
				//ExternalInterface.addCallback("SetButtonDimensions", setButtonDimensions);
				//ExternalInterface.addCallback("SetButtonText", this.SetButtonText);
				//ExternalInterface.addCallback("SetButtonTextPadding", this.SetButtonTextPadding);
				//ExternalInterface.addCallback("SetButtonTextStyle", this.SetButtonTextStyle);
				//ExternalInterface.addCallback("SetButtonAction", this.SetButtonAction);
				//ExternalInterface.addCallback("SetButtonDisabled", this.SetButtonDisabled);
			} catch (ex:Error) 
			{
				this.Debug("Callbacks where not set: " + ex.message);
				return;
			}
			
			//ExternalCall.Simple(this.cleanUp_Callback);
		}
		
		private function loadPostParams(param_string:String):Object {			
			var post_object:Object = {};
			
			if (param_string != null) {
				var name_value_pairs:Array = param_string.split("&amp;");
				
				for (var i:Number = 0; i < name_value_pairs.length; i++) {
					var name_value:String = String(name_value_pairs[i]);
					var index_of_equals:Number = name_value.indexOf("=");
					if (index_of_equals > 0) {
						post_object[decodeURIComponent(name_value.substring(0, index_of_equals))] = decodeURIComponent(name_value.substr(index_of_equals + 1));
					}
				}
			}
			
			return post_object;
		}
	}
}

