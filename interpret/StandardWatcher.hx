package interpret;

import sys.io.File;
import sys.FileSystem;
import haxe.Timer;
/** Standard watcher implementation based on haxe's Sys API.
    A watcher is reused and can watch multiple paths at the same time. */
class StandardWatcher implements Watcher {

    public static var UPDATE_INTERVAL:Float = 1.0;

    var timer:Timer;

    var watched:Map<String,WatchedFile>;

    public function new() {

        timer = new Timer(Math.round(UPDATE_INTERVAL * 1000));
        timer.run = tick;
        watched = new Map();

    } //new

    public function watch(path:String, onUpdate:String->Void):Void->Void {

        #if !sys
        throw 'Cannot watch file at path $path with StandardWatcher on this target';
        #end

        var watchedFile = watched.get(path);
        if (watchedFile == null) {
            watchedFile = new WatchedFile();
            watched.set(path, watchedFile);
        }
        watchedFile.updateCallbacks.push(onUpdate);

        var stopped = false;
        var stopWatching = function() {
            if (stopped) return;
            stopped = true;
            var watchedFile = watched.get(path);
            watchedFile.updateCallbacks.remove(onUpdate);
            if (watchedFile.updateCallbacks.length == 0) {
                watched.remove(path);
            }
        };

        return stopWatching;

    } //watch

    function tick() {

        for (path in watched.keys()) {
            if (FileSystem.exists(path) && !FileSystem.isDirectory(path)) {
                var stat = FileSystem.stat(path);
                var watchedFile = watched.get(path);
                if (watchedFile.mtime != -1 && stat.mtime.getTime() > watchedFile.mtime) {
                    // File modification time has changed
                    watchedFile.mtime = stat.mtime.getTime();
                    var content = File.getContent(path);

                    if (content != watchedFile.content) {
                        watchedFile.content = content;
                        
                        // File content has changed, notify
                        for (i in 0...watchedFile.updateCallbacks.length) {
                            watchedFile.updateCallbacks[i](watchedFile.content);
                        }
                    }

                }
                else if (watchedFile.mtime == -1) {
                    // Fetch modification time and content to compare it later
                    watchedFile.mtime = stat.mtime.getTime();
                    watchedFile.content = File.getContent(path);
                }
            }
            #if interpret_debug_watch
            else {
                trace('[warning] Cannot watch file because it does not exist or is not a file: $path');
            }
            #end
        }

    } //tick

} //StandardWatcher

@:allow(interpret.StandardWatcher)
private class WatchedFile {

    public var updateCallbacks:Array<String->Void> = [];

    public var mtime:Float = -1;

    public var content:String = null;

    public function new() {}

} //WatchedFile
