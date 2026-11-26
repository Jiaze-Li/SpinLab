// Resolve a base64 NSURL bookmark to its path without UI or mounting (used by prod_fingerprint.sh).

ObjC.import('Foundation');
function run(a){var d=$.NSData.alloc.initWithBase64EncodedStringOptions(a[0],0);if(!d.js&&!d.length)throw new Error('bad base64');
var u=$.NSURL.URLByResolvingBookmarkDataOptionsRelativeToURLBookmarkDataIsStaleError(d,512|256,$(),$(),$());
if(!u||!u.path)throw new Error('unresolvable');return ObjC.unwrap(u.path);}
