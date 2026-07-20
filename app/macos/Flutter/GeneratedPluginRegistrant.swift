//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import clipboard
import desktop_drop
import file_selector_macos
import media_kit_libs_macos_video
import media_kit_video
import package_info_plus
import url_launcher_macos
import volume_controller
import wakelock_plus

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  ClipboardPlugin.register(with: registry.registrar(forPlugin: "ClipboardPlugin"))
  DesktopDropPlugin.register(with: registry.registrar(forPlugin: "DesktopDropPlugin"))
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  MediaKitLibsMacosVideoPlugin.register(with: registry.registrar(forPlugin: "MediaKitLibsMacosVideoPlugin"))
  MediaKitVideoPlugin.register(with: registry.registrar(forPlugin: "MediaKitVideoPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  UrlLauncherPlugin.register(with: registry.registrar(forPlugin: "UrlLauncherPlugin"))
  VolumeControllerPlugin.register(with: registry.registrar(forPlugin: "VolumeControllerPlugin"))
  WakelockPlusMacosPlugin.register(with: registry.registrar(forPlugin: "WakelockPlusMacosPlugin"))
}
