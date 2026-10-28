import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:nasio_client/main.dart' as app;

/// AI / MCP UI 自动化调试入口
/// 使用方式：
///   flutter run -t test_driver/main_driver.dart -d windows
/// 或通过 Dart MCP Server 的 launch_app 工具指定 target: "test_driver/main_driver.dart"
void main() {
  // 开启 Flutter Driver VM Service 扩展，默认保留物理键盘输入能力；
  // AI 调用 enter_text 时可通过 flutter_driver_command(set_text_entry_emulation) 动态切换。
  enableFlutterDriverExtension(enableTextEntryEmulation: false);

  app.main();

  // 确保语义树开启，支持按 SemanticsLabel 检索组件及 Web 端 DOM 语义节点生成
  SemanticsBinding.instance.ensureSemantics();

  // Windows 桌面端窗口处于后台或被 IDE 遮挡时，系统 DWM 可能会节流 vsync 信号导致 Driver 响应卡顿；
  // 当检测到存在挂起的待渲染帧时，主动触发 scheduleWarmUpFrame 推进 UI 帧完成渲染。
  Timer.periodic(const Duration(milliseconds: 60), (_) {
    final binding = WidgetsBinding.instance;
    if (binding.hasScheduledFrame) {
      binding.scheduleWarmUpFrame();
    }
  });
}

