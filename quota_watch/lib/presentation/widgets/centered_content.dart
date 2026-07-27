// 居中限宽容器：宽屏时限制正文最大宽度并居中，窄屏时占满可用宽度。

import 'package:flutter/material.dart';

class CenteredContent extends StatelessWidget {
  // 正文允许的最大宽度；超过后只增加两侧留白。
  final double maxWidth;
  final Widget child;

  const CenteredContent({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Align 负责水平居中；ConstrainedBox 只限制最大宽度，不影响高度。
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // SizedBox 让子 Widget 在没达到最大宽度时仍占满可用宽度。
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
