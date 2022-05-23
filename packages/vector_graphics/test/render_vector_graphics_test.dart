// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/src/listener.dart';
import 'package:vector_graphics/src/render_vector_graphics.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

void main() {
  late PictureInfo pictureInfo;

  setUpAll(() {
    final VectorGraphicsBuffer buffer = VectorGraphicsBuffer();
    const VectorGraphicsCodec().writeSize(buffer, 30, 50);

    pictureInfo = decodeVectorGraphics(
      buffer.done(),
      locale: const Locale('fr', 'CH'),
      textDirection: TextDirection.ltr,
    );
  });

  test('Rasterizes a picture to a draw image call', () async {
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      null,
    );
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(100, 100)));
    final FakePaintingContext context = FakePaintingContext();
    renderVectorGraphic.paint(context, Offset.zero);

    // No rasterization yet.
    expect(context.canvas.lastImage, isNull);

    await renderVectorGraphic.pendingRasterUpdate;

    // When the rasterization is finished, it marks self as needing paint.
    expect(renderVectorGraphic.debugNeedsPaint, true);

    renderVectorGraphic.paint(context, Offset.zero);

    expect(context.canvas.lastImage, isNotNull);
  });

  test('Changing color filter does not re-rasterize', () async {
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      null,
    );
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(100, 100)));
    final FakePaintingContext context = FakePaintingContext();
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;
    renderVectorGraphic.paint(context, Offset.zero);

    final ui.Image firstImage = context.canvas.lastImage!;

    renderVectorGraphic.colorFilter =
        const ui.ColorFilter.mode(Colors.red, ui.BlendMode.colorBurn);
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;

    expect(firstImage.debugDisposed, false);

    renderVectorGraphic.paint(context, Offset.zero);

    expect(context.canvas.lastImage, equals(firstImage));
  });

  test('Changing device pixel ratio does re-rasterize and dispose old raster',
      () async {
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      null,
    );
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(100, 100)));
    final FakePaintingContext context = FakePaintingContext();
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;
    renderVectorGraphic.paint(context, Offset.zero);

    final ui.Image firstImage = context.canvas.lastImage!;

    renderVectorGraphic.devicePixelRatio = 2.0;
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;

    expect(firstImage.debugDisposed, true);

    renderVectorGraphic.paint(context, Offset.zero);

    expect(context.canvas.lastImage!.debugDisposed, false);
  });

  test('Changing size does re-rasterize and dispose old raster', () async {
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      null,
    );
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(100, 100)));
    final FakePaintingContext context = FakePaintingContext();
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;
    renderVectorGraphic.paint(context, Offset.zero);

    final ui.Image firstImage = context.canvas.lastImage!;

    // change size.
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(1000, 1000)));
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;

    expect(firstImage.debugDisposed, true);

    renderVectorGraphic.paint(context, Offset.zero);

    expect(context.canvas.lastImage!.debugDisposed, false);
  });

  test('Does not rasterize a picture when fully transparent', () async {
    final FixedOpacityAnimation opacity = FixedOpacityAnimation(0.0);
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      opacity,
    );
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(100, 100)));
    final FakePaintingContext context = FakePaintingContext();
    renderVectorGraphic.paint(context, Offset.zero);

    // No rasterization yet.
    expect(context.canvas.lastImage, isNull);
    expect(renderVectorGraphic.pendingRasterUpdate, isNull);

    opacity.value = 1.0;
    opacity.notifyListeners();

    // Changing opacity requires painting.
    expect(renderVectorGraphic.debugNeedsPaint, true);

    renderVectorGraphic.paint(context, Offset.zero);

    // Rasterization is now pending.
    expect(renderVectorGraphic.pendingRasterUpdate, isNotNull);
  });

  test('Disposing render object disposes picture', () async {
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      null,
    );
    renderVectorGraphic.layout(BoxConstraints.tight(const Size(100, 100)));
    final FakePaintingContext context = FakePaintingContext();
    renderVectorGraphic.paint(context, Offset.zero);
    await renderVectorGraphic.pendingRasterUpdate;

    renderVectorGraphic.paint(context, Offset.zero);

    final ui.Image lastImage = context.canvas.lastImage!;

    renderVectorGraphic.dispose();

    expect(lastImage.debugDisposed, true);
  });

  test('Removes listeners on detach, dispose, adds then on attach', () async {
    final FixedOpacityAnimation opacity = FixedOpacityAnimation(0.5);
    final RenderVectorGraphic renderVectorGraphic = RenderVectorGraphic(
      pictureInfo,
      null,
      1.0,
      opacity,
    );
    final PipelineOwner pipelineOwner = PipelineOwner();
    expect(opacity._listeners, hasLength(1));

    renderVectorGraphic.attach(pipelineOwner);
    expect(opacity._listeners, hasLength(1));

    renderVectorGraphic.detach();
    expect(opacity._listeners, hasLength(0));

    renderVectorGraphic.attach(pipelineOwner);
    expect(opacity._listeners, hasLength(1));

    renderVectorGraphic.dispose();
    expect(opacity._listeners, hasLength(0));
  });
}

class FakeCanvas extends Fake implements Canvas {
  ui.Image? lastImage;
  Rect? lastSrc;
  Rect? lastDst;
  Paint? lastPaint;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    lastImage = image;
    lastSrc = src;
    lastDst = dst;
    lastPaint = paint;
  }
}

class FakePaintingContext extends Fake implements PaintingContext {
  @override
  final FakeCanvas canvas = FakeCanvas();
}

class FixedOpacityAnimation extends Animation<double> {
  FixedOpacityAnimation(this.value);

  final Set<ui.VoidCallback> _listeners = <ui.VoidCallback>{};

  @override
  void addListener(ui.VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void addStatusListener(AnimationStatusListener listener) {
    throw UnsupportedError('addStatusListener');
  }

  @override
  void removeListener(ui.VoidCallback listener) {
    _listeners.remove(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    throw UnsupportedError('removeStatusListener');
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  double value = 1.0;

  void notifyListeners() {
    for (ui.VoidCallback listener in _listeners) {
      listener();
    }
  }
}