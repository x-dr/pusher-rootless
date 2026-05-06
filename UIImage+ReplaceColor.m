#import "UIImage+ReplaceColor.h"

@implementation UIImage (ReplaceColor)

- (UIImage *)imageByReplacingColor:(UIColor *)sourceColor withColor:(UIColor *)targetColor {

  // 将源颜色拆成 0-255 的 RGBA 分量，便于和位图像素直接比较。
  const CGFloat *sourceComponents = CGColorGetComponents(sourceColor.CGColor);
  UInt8 *source255Components = malloc(sizeof(UInt8) * 4);
  for (int i = 0; i < 4; i++) source255Components[i] = (UInt8) round(sourceComponents[i] * 255.0);

  // 目标颜色同样转换成 0-255 分量，后面用于混合替换。
  const CGFloat *targetComponents = CGColorGetComponents(targetColor.CGColor);
  UInt8 *target255Components = malloc(sizeof(UInt8) * 4);
  for (int i = 0; i < 4; i++) target255Components[i] = (UInt8) round(targetComponents[i] * 255.0);

  // 原始 CGImage 引用，后续绘制到可写的 bitmap context。
  CGImageRef rawImage = self.CGImage;

  // 图片尺寸。
  size_t width = CGImageGetWidth(rawImage);
  size_t height = CGImageGetHeight(rawImage);
  CGRect rect = { CGPointZero, { width, height } };

  // 使用 8-bit RGBA，和下面每 4 字节遍历一个像素保持一致。
  size_t bitsPerComponent = 8;
  size_t bytesPerRow = width * 4;
  CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;

  // 像素缓冲区由 CoreGraphics 写入，处理完成后需要手动释放。
  UInt8 *data = calloc(bytesPerRow, height);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

  // 创建位图上下文并把原图绘制进去，获得可修改的像素数据。
  CGContextRef ctx = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  CGContextDrawImage(ctx, rect, rawImage);

  // 遍历每个像素：颜色越接近源颜色，越倾向替换成目标颜色。
  for (int byte = 0; byte < bytesPerRow * height; byte += 4) {

      UInt8 r = data[byte];
      UInt8 g = data[byte + 1];
      UInt8 b = data[byte + 2];

      // 分别计算 RGB 分量与源颜色的差距。
      UInt8 dr = abs(r - source255Components[0]);
      UInt8 dg = abs(g - source255Components[1]);
      UInt8 db = abs(b - source255Components[2]);

      // ratio 表示当前像素离源颜色有多远；距离太大时保持原色。
      CGFloat ratio = (dr+dg+db)/(255.0*3.0);
      if (ratio > 0.1) ratio = 1; // if ratio is too far away, set it to max.
      if (ratio < 0) ratio = 0; // if ratio isn't far enough away, set it to min.

      // 按距离混合原色和目标色，让边缘过渡更自然。
      data[byte] = (UInt8) round(ratio * r) + (UInt8) round((1.0 - ratio) * target255Components[0]);
      data[byte + 1] = (UInt8) round(ratio * g) + (UInt8) round((1.0 - ratio) * target255Components[1]);
      data[byte + 2] = (UInt8) round(ratio * b) + (UInt8) round((1.0 - ratio) * target255Components[2]);

  }

  // 从上下文生成新图片。
  CGImageRef img = CGBitmapContextCreateImage(ctx);

  // 释放 CoreGraphics 对象和手动分配的内存。
  CGContextRelease(ctx);
  CGColorSpaceRelease(colorSpace);
  free(data);
  free(source255Components);
  free(target255Components);

  // 保留 Retina scale，避免生成的新图在界面里发虚。
  UIImage *newImage = [UIImage imageWithCGImage:img scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp];
  CGImageRelease(img);

  return newImage;

}

@end
