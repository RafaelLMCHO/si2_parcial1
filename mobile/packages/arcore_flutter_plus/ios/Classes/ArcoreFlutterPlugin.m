#import "ArcoreFlutterPlugin.h"
#import <arcore_flutter_plus/arcore_flutter_plus-Swift.h>

@implementation ArcoreFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftArcoreFlutterPlugin registerWithRegistrar:registrar];
}
@end
