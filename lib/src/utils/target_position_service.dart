/*
 * Copyright (c) 2021 Simform Solutions
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class TargetPositionService {
  /// A service class that handles positioning calculations for showcase
  /// targets.
  ///
  /// This class calculates and provides the position and dimensions of a
  /// target widget within the context of the showcase overlay. It's
  /// responsible for:
  ///
  /// - Determining the exact position of a target widget in global coordinates.
  /// - Computing the boundaries of the target widget with optional padding.
  /// - Providing helper methods for tooltip positioning around the target.
  /// - Ensuring the target stays within screen bounds.
  /// - Supporting different ancestral coordinate systems.
  TargetPositionService({
    required this.renderBox,
    required this.screenSize,
    this.padding = EdgeInsets.zero,
    this.rootRenderObject,
  }) {
    _getRenderBoxOffset();
  }

  final RenderBox? renderBox;
  final EdgeInsets padding;
  final Size screenSize;
  final RenderObject? rootRenderObject;

  Offset? _boxOffset;

  /// The target's bounding rect after applying all ancestor transforms
  /// (e.g., FittedBox scaling). This gives the actual on-screen size.
  Rect? _transformedRect;

  /// The on-screen size of the target after ancestor transforms.
  Size get _size => _transformedRect?.size ?? renderBox?.size ?? Size.zero;

  // Caching fields to avoid redundant calculations
  Rect? _cachedRect;
  Rect? _cachedRectForOverlay;

  // Flag to track if dimensions have changed and cache needs to be invalidated
  bool _dimensionsChanged = true;

  /// Calculates the rectangle representing the target widget with padding
  ///
  /// This method returns a rectangle that represents the target widget's bounds
  /// including any padding, clamped to stay within the screen boundaries.
  /// Used by the showcase system to determine where to draw highlight effects.
  Rect getRect() {
    if (_checkBoxOrOffsetIsNull(checkDy: true, checkDx: true)) {
      return Rect.zero;
    }

    // Use cached value if available and dimensions haven't changed
    if (_cachedRect != null && !_dimensionsChanged) {
      return _cachedRect!;
    }

    final topLeft = _size.topLeft(_boxOffset!);
    final bottomRight = _size.bottomRight(_boxOffset!);
    final leftDx = topLeft.dx - padding.left;
    final leftDy = topLeft.dy - padding.top;

    _dimensionsChanged = false;
    return _cachedRect = Rect.fromLTRB(
      leftDx.clamp(0, double.maxFinite),
      leftDy.clamp(0, double.maxFinite),
      min(bottomRight.dx + padding.right, screenSize.width),
      min(bottomRight.dy + padding.bottom, screenSize.height),
    );
  }

  /// Gets the raw rectangle bounds of the target widget without clamping
  ///
  /// Unlike [getRect], this method returns the exact rectangle of the target widget
  /// without applying any screen boundary constraints. It's used by the showcase
  /// controller to create the cutout area in the overlay where the target widget
  /// will be visible.
  Rect getRectForOverlay() {
    if (_checkBoxOrOffsetIsNull(checkDy: true, checkDx: true)) {
      return Rect.zero;
    }

    // Use cached value if available and dimensions haven't changed
    if (_cachedRectForOverlay != null && !_dimensionsChanged) {
      return _cachedRectForOverlay!;
    }

    final topLeft = _size.topLeft(_boxOffset!);
    final bottomRight = _size.bottomRight(_boxOffset!);

    _dimensionsChanged = false;
    return _cachedRectForOverlay = Rect.fromLTRB(
      topLeft.dx,
      topLeft.dy,
      bottomRight.dx,
      bottomRight.dy,
    );
  }

  /// Gets the bottom edge position of the target widget with padding.
  double getBottom() {
    if (_checkBoxOrOffsetIsNull(checkDy: true)) return padding.bottom;
    final bottomRight = _size.bottomRight(_boxOffset!);
    return bottomRight.dy + padding.bottom;
  }

  /// Gets the top edge position of the target widget with padding.
  double getTop() {
    if (_checkBoxOrOffsetIsNull(checkDy: true)) return -padding.top;
    final topLeft = _size.topLeft(_boxOffset!);
    return topLeft.dy - padding.top;
  }

  /// Gets the left edge position of the target widget with padding.
  double getLeft() {
    if (_checkBoxOrOffsetIsNull(checkDx: true)) return -padding.left;
    final topLeft = _size.topLeft(_boxOffset!);
    return topLeft.dx - padding.left;
  }

  /// Gets the right edge position of the target widget with padding.
  double getRight() {
    if (_checkBoxOrOffsetIsNull(checkDx: true)) return padding.right;
    final bottomRight = _size.bottomRight(_boxOffset!);
    return bottomRight.dx + padding.right;
  }

  /// Calculates the total height of the target widget including padding.
  double getHeight() => getBottom() - getTop();

  /// Calculates the total width of the target widget including padding.
  double getWidth() => getRight() - getLeft();

  /// Calculates the horizontal center position of the target widget.
  double getCenter() => (getLeft() + getRight()) * 0.5;

  /// Gets the top-left corner of the render box in global coordinates.
  Offset topLeft() {
    if (_transformedRect != null) return _transformedRect!.topLeft;

    final box = renderBox;
    if (box == null) return Offset.zero;

    return box.size.topLeft(
      box.localToGlobal(Offset.zero, ancestor: rootRenderObject),
    );
  }

  /// Gets the center position of the target widget in global coordinates.
  Offset getOffset() => _size.center(topLeft());

  /// Calculates and stores the global position of the render box.
  ///
  /// Uses [MatrixUtils.transformRect] to account for ancestor transforms
  /// (e.g., [FittedBox] scaling). This gives the actual on-screen position
  /// and size rather than the raw layout dimensions.
  void _getRenderBoxOffset() {
    if (renderBox == null) return;

    // Compute the full transform from the target to the root overlay.
    // This accounts for FittedBox, Transform, and any other ancestor
    // that applies a paint transform.
    final matrix = renderBox!.getTransformTo(rootRenderObject);
    _transformedRect = MatrixUtils.transformRect(
      matrix,
      Offset.zero & renderBox!.size,
    );
    _boxOffset = _transformedRect!.topLeft;
  }

  /// Checks if the render box or its offset are null or have invalid
  /// components.
  ///
  /// This helper method is used internally to safely handle cases where
  /// position calculations might fail due to missing or invalid render
  /// information.
  ///
  /// * [checkDy] - Whether to check if the y-coordinate is valid
  /// * [checkDx] - Whether to check if the x-coordinate is valid
  bool _checkBoxOrOffsetIsNull({bool checkDy = false, bool checkDx = false}) {
    return renderBox == null ||
        _boxOffset == null ||
        (checkDx && (_boxOffset?.dx.isNaN ?? true)) ||
        (checkDy && (_boxOffset?.dy.isNaN ?? true));
  }
}
