import CFNetwork
import Flutter
import UIKit

public class FlutterSystemProxyPlugin: NSObject, FlutterPlugin {
  static var proxyCache : [String: [String: Any]] = [:]
  private static var cachedProxySettingsSignature: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_system_proxy", binaryMessenger: registrar.messenger())
    let instance = FlutterSystemProxyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDeviceProxy":
        FlutterSystemProxyPlugin.invalidateCacheIfProxySettingsChanged()
        let args = call.arguments as! NSDictionary
        let url = args.value(forKey:"url") as! String
        var dict:[String:Any]? = [:]
        if(FlutterSystemProxyPlugin.proxyCache[url] != nil){
            let res = FlutterSystemProxyPlugin.proxyCache[url]
            if(res != nil){
                dict = res
            }
        } 
        else 
        {
            let res = FlutterSystemProxyPlugin.resolve(url: url)
            if(res != nil){
                dict = res
            }
        }
        result(dict)
        break
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func resolve(url:String)->[String:Any]?{
        if(FlutterSystemProxyPlugin.proxyCache[url] != nil){
            return FlutterSystemProxyPlugin.proxyCache[url]
        }
      let proxConfigDict = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as NSDictionary?
      if proxConfigDict != nil {
          if(proxConfigDict?[kCFNetworkProxiesProxyAutoConfigEnable] as? Int == 1){
                let pacUrl = proxConfigDict?[kCFNetworkProxiesProxyAutoConfigURLString] as! String?
                let pacContent = proxConfigDict?[kCFNetworkProxiesProxyAutoConfigJavaScript] as! String?
                if(pacContent != nil){
                    self.handlePacContent(pacContent: pacContent!, url: url)
                }else if(pacUrl != nil){
                    self.handlePacUrl(pacUrl: pacUrl!,url: url)
                }
            } else if (proxConfigDict![kCFNetworkProxiesHTTPEnable] as? Int == 1){
                var dict: [String: Any] = [:]
                dict["host"] = proxConfigDict![kCFNetworkProxiesHTTPProxy] as? String
                dict["port"] = proxConfigDict![kCFNetworkProxiesHTTPPort] as? Int
                FlutterSystemProxyPlugin.proxyCache[url] = dict
            }
        }
        return FlutterSystemProxyPlugin.proxyCache[url]
    }
    
    static func handlePacContent(pacContent: String,url: String){
        let proxies = CFNetworkCopyProxiesForAutoConfigurationScript(pacContent as CFString, CFURLCreateWithString(kCFAllocatorDefault, url as CFString, nil), nil)!.takeUnretainedValue() as? [[CFString: Any]] ?? [];
        if(proxies.count > 0){
            let proxy = proxies.first{$0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTP || $0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTPS}
            if(proxy != nil){
                let host = proxy?[kCFProxyHostNameKey] ?? nil
                let port = proxy?[kCFProxyPortNumberKey] ?? nil
                var dict:[String: Any] = [:]
                dict["host"] = host
                dict["port"] = port
                FlutterSystemProxyPlugin.proxyCache[url] = dict
            }
        }
    }

    static func handlePacUrl(pacUrl: String, url: String){
        let _pacUrl = CFURLCreateWithString(kCFAllocatorDefault,  pacUrl as CFString?,nil)
        let targetUrl = CFURLCreateWithString(kCFAllocatorDefault, url as CFString?, nil)
        var info = url;
        withUnsafeMutablePointer(to: &info, { infoPointer in
            var context:CFStreamClientContext = CFStreamClientContext.init(version: 0, info: infoPointer, retain: nil, release: nil, copyDescription: nil)
                let runLoopSource = CFNetworkExecuteProxyAutoConfigurationURL(_pacUrl!,targetUrl!,  { client, proxies, error in
                    let _proxies = proxies as? [[CFString: Any]] ?? [];
                        if(_proxies.count > 0){
                        let proxy = _proxies.first{$0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTP || $0[kCFProxyTypeKey] as! CFString == kCFProxyTypeHTTPS}
                        if(proxy != nil){
                            let host = proxy?[kCFProxyHostNameKey] ?? nil
                            let port = proxy?[kCFProxyPortNumberKey] ?? nil
                            var dict:[String: Any] = [:]
                            dict["host"] = host
                            dict["port"] = port
                            let url = client.assumingMemoryBound(to: String.self).pointee
                            FlutterSystemProxyPlugin.proxyCache[url] = dict
                        }
                    }
                    CFRunLoopStop(CFRunLoopGetCurrent());
                }, &context);
                let runLoop = CFRunLoopGetCurrent();
                CFRunLoopAddSource(runLoop, getRunLoopSource(runLoopSource), CFRunLoopMode.defaultMode);
                CFRunLoopRun();
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), getRunLoopSource(runLoopSource), CFRunLoopMode.defaultMode);
        })
    }
    
    //For backward compatibility <= XCode 15
    static func getRunLoopSource<T>(_ runLoopSource: T) -> CFRunLoopSource {
        if let unmanagedValue = runLoopSource as? Unmanaged<CFRunLoopSource> {
            return unmanagedValue.takeUnretainedValue()
        } else {
            return runLoopSource as! CFRunLoopSource
        }
    }

    private static func invalidateCacheIfProxySettingsChanged() {
        let signature = proxySettingsSignature()
        if cachedProxySettingsSignature != signature {
            proxyCache.removeAll(keepingCapacity: true)
            cachedProxySettingsSignature = signature
        }
    }

    private static func proxySettingsSignature() -> String {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as? NSDictionary else {
            return ""
        }

        let signatureComponents: [Any] = [
            settings[kCFNetworkProxiesProxyAutoConfigEnable] ?? NSNull(),
            settings[kCFNetworkProxiesProxyAutoConfigURLString] ?? NSNull(),
            settings[kCFNetworkProxiesProxyAutoConfigJavaScript] ?? NSNull(),
            settings[kCFNetworkProxiesHTTPEnable] ?? NSNull(),
            settings[kCFNetworkProxiesHTTPProxy] ?? NSNull(),
            settings[kCFNetworkProxiesHTTPPort] ?? NSNull(),
        ]

        return signatureComponents.map { String(describing: $0) }.joined(separator: "\u{1F}")
    }
    
}