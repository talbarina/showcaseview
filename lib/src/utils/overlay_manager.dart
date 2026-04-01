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

import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/linked_showcase_data_model.dart';
import '../showcase/showcase.dart';
import '../showcase/showcase_controller.dart';
import '../showcase/showcase_service.dart';
import '../showcase/showcase_view.dart';
import 'extensions.dart';
import 'linked_showcase_data_model_tween.dart';
import 'shape_clipper.dart';

/// A singleton manager class responsible for displaying and controlling
/// overlays in the ShowcaseView.
///
/// This class manages the creation, display, and removal of overlays used by
/// the showcase system. It coordinates with [ShowcaseView] to control
/// overlay visibility and maintains the current showcase scope.
class OverlayManager {
  /// Private constructor for singleton implementation
  OverlayManager._();

  /// Singleton instance of the manager
  static final _instance = OverlayManager._();

  /// Public accessor for the singleton instance
  static OverlayManager get instance => _instance;

  /// The overlay state where entries will be inserted
  OverlayState? overlayState;

  /// Current overlay entry being displayed
  OverlayEntry? _overlayEntry;

  /// Controls the fade-in / fade-out of the entire overlay (tour start/end).
  AnimationController? _fadeController;

  /// Controls the fade of tooltip widgets between steps.
  AnimationController? _stepFadeController;

  /// Controls the cutout morph animation between steps.
  AnimationController? _clipMorphController;

  /// Clip data for the previous step (source of morph animation).
  List<LinkedShowcaseDataModel> _previousClipData = [];

  /// Clip data for the current step (target of morph animation).
  List<LinkedShowcaseDataModel> _currentClipData = [];

  /// Whether a step transition is in progress.
  bool _isTransitioning = false;

  /// Duration of the overlay fade-in / fade-out animation (tour start/end).
  static const _fadeDuration = Duration(milliseconds: 200);

  /// Duration of the tooltip fade between steps.
  static const _stepFadeDuration = Duration(milliseconds: 150);

  /// Duration of the cutout morph animation between steps.
  static const _clipMorphDuration = Duration(milliseconds: 300);

  /// Flag to determine if overlay should be shown
  var _shouldShow = false;

  /// The current showcase scope identifier
  String get _currentScope => ShowcaseService.instance.currentScope;

  /// Returns whether an overlay is currently being displayed
  bool get _isShowing => _overlayEntry != null;

  /// Updates the overlay visibility based on the provided showcase view.
  ///
  /// This method is called from showcase widgets to control overlay visibility.
  /// If the scope has changed, it will dispose the previous overlay.
  ///
  /// * [show] - Whether to show or hide the overlay.
  /// * [scope] - The new scope to be set as current.
  void update({
    required bool show,
    required String scope,
  }) {
    if (_currentScope != scope) {
      ShowcaseService.instance.updateCurrentScope(scope);
    }
    _shouldShow = show;
    _sync();
  }

  /// Updates the overlay state reference used by the manager
  ///
  /// This method allows setting or updating the [OverlayState] that will be
  /// used for inserting overlay entries.
  ///
  /// * [overlayState] - The new overlay state to use, can be null
  void updateState(OverlayState? overlayState) =>
      this.overlayState = overlayState;

  /// Disposes the overlay for the specified scope.
  ///
  /// Hides the overlay if it's currently showing and matches the provided
  /// scope.
  ///
  /// * [scope] - The scope to dispose overlays for
  void dispose({required String scope}) {
    if (!_isShowing || _currentScope != scope) return;
    _disposeControllers();
    _removeOverlay();
  }

  /// Shows the overlay using the provided builder.
  ///
  /// Creates a new overlay entry if none exists, otherwise rebuilds the
  /// existing one.
  void _show(WidgetBuilder overlayBuilder) {
    if (_overlayEntry != null) {
      // Rebuild overlay.
      _rebuild();
      return;
    }

    final vsync = overlayState!;

    // Create all animation controllers.
    _disposeControllers();
    _fadeController = AnimationController(
      vsync: vsync,
      duration: _fadeDuration,
    );
    _stepFadeController = AnimationController(
      vsync: vsync,
      duration: _stepFadeDuration,
      value: 1.0, // start fully visible
    );
    _clipMorphController = AnimationController(
      vsync: vsync,
      duration: _clipMorphDuration,
      value: 1.0, // start at end position (no morph on first step)
    );

    // Reset clip data.
    _previousClipData = [];
    _currentClipData = [];

    // Create and insert the overlay entry.
    _overlayEntry = OverlayEntry(builder: overlayBuilder);
    overlayState?.insert(_overlayEntry!);

    // Animate the overlay in.
    _fadeController!.forward();
  }

  /// Removes and clears the current overlay entry with a fade-out animation.
  Future<void> _hide() async {
    // Animate out before removing.
    final controller = _fadeController;
    if (controller != null && controller.isCompleted) {
      await controller.reverse();
    }
    _removeOverlay();
    _disposeControllers();
  }

  /// Removes the overlay entry without animation.
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Synchronizes the overlay visibility with the showcase manager state.
  ///
  /// Shows or hides the overlay based on the [_shouldShow] flag.
  void _sync() {
    if (_isShowing && !_shouldShow) {
      _hide();
    } else if (!_isShowing && _shouldShow) {
      _show(_getBuilder);
    } else {
      _rebuild();
    }
  }

  /// Creates and returns the overlay widget structure.
  ///
  /// Builds a stack with background and tooltip widgets based on active
  /// controllers.
  Widget _getBuilder(BuildContext context) {
    if (!context.mounted || !(_overlayEntry?.mounted ?? true)) {
      return const SizedBox.shrink();
    }

    final showcaseView = ShowcaseView.getNamed(_currentScope);
    final controllers = ShowcaseService.instance
            .getControllers(
              scope: showcaseView.scope,
            )[showcaseView.getActiveShowcaseKey]
            ?.values
            .toList() ??
        <ShowcaseController>[];

    if (controllers.isEmpty) return const SizedBox.shrink();

    final currentShowcaseKey = showcaseView.getActiveShowcaseKey;

    late final ShowcaseController firstController;
    late final Showcase firstShowcaseConfig;
    final controllerLength = controllers.length;
    for (var i = 0; i < controllerLength; i++) {
      final controller = controllers[i];
      if (i == 0) {
        firstController = controller;
        firstShowcaseConfig = firstController.config;
      }
      if (controller.key == currentShowcaseKey) {
        controller.updateControllerData();
      }
    }

    // Update current clip data from controllers.
    _currentClipData = _getLinkedShowcasesData(controllers);

    // If previous clip data is empty (first step), use current.
    if (_previousClipData.isEmpty) {
      _previousClipData = _currentClipData;
    }

    final backgroundContainer = ColoredBox(
      color: firstShowcaseConfig.overlayColor
          .reduceOpacity(firstShowcaseConfig.overlayOpacity),
      child: const Align(),
    );

    // Build the overlay stack with separate animation layers.
    final overlayChild = Stack(
      children: [
        // Layer 1: Scrim + blur + cutout — animated clip morph, no fade.
        GestureDetector(
          onTap: firstController.handleBarrierTap,
          child: AnimatedBuilder(
            animation: _clipMorphController!,
            builder: (context, child) {
              final interpolatedData = lerpLinkedShowcaseDataList(
                _previousClipData,
                _currentClipData,
                _clipMorphController!.value,
              );
              return ClipPath(
                clipper: ShapeClipper(linkedObjectData: interpolatedData),
                child: child,
              );
            },
            child: firstController.blur <= 0.2
                ? backgroundContainer
                : BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: firstController.blur,
                      sigmaY: firstController.blur,
                    ),
                    child: backgroundContainer,
                  ),
          ),
        ),
        // Layer 2: Tooltip widgets — step fade only.
        FadeTransition(
          opacity: _stepFadeController!,
          child: Stack(
            children: [
              ...controllers.expand((object) => object.tooltipWidgets),
            ],
          ),
        ),
      ],
    );

    final inheritedData = firstController.inheritedData;

    // Wrap the child with captured themes to maintain the original context's
    // theme. Captured themes are used as to cover cases where there are
    // multiple themes in the widget tree.
    final themedChild = inheritedData.capturedThemes.wrap(overlayChild);

    // Wrap with other inherited widgets to maintain showcase's context's
    // inherited values.
    final content = Directionality(
      textDirection: inheritedData.textDirection,
      child: MediaQuery(
        data: inheritedData.mediaQuery,
        child: DefaultTextStyle(
          style: inheritedData.textStyle,
          child: themedChild,
        ),
      ),
    );

    // Wrap with fade animation for tour start/end.
    if (_fadeController != null) {
      return FadeTransition(opacity: _fadeController!, child: content);
    }
    return content;
  }

  /// Extracts and returns linked showcase data from controllers.
  ///
  /// Filters out null data and collects valid linked showcase information.
  List<LinkedShowcaseDataModel> _getLinkedShowcasesData(
    List<ShowcaseController> controllers,
  ) {
    final controllerLength = controllers.length;
    return [
      for (var i = 0; i < controllerLength; i++)
        if (controllers[i].linkedShowcaseDataModel case final model?) model,
    ];
  }

  /// Forces the overlay entry to rebuild.
  ///
  /// When animation controllers are active, the rebuild is wrapped in a
  /// step transition: fade out tooltips → morph cutout → fade in tooltips.
  /// The scrim and blur stay constant throughout.
  void _rebuild() {
    final stepFade = _stepFadeController;
    final clipMorph = _clipMorphController;

    if (stepFade != null &&
        clipMorph != null &&
        stepFade.isCompleted &&
        !_isTransitioning) {
      _isTransitioning = true;

      // 1. Fade out tooltips.
      stepFade.reverse().then((_) {
        // 2. Snapshot the old clip data and rebuild to get new data.
        _previousClipData = List.of(_currentClipData);
        _overlayEntry?.markNeedsBuild();

        // 3. Morph the cutout from old to new position.
        clipMorph.forward(from: 0.0).then((_) {
          // 4. Fade in new tooltips.
          stepFade.forward().then((_) {
            _isTransitioning = false;
          });
        });
      });
    } else if (!_isTransitioning) {
      _overlayEntry?.markNeedsBuild();
    }
  }

  /// Safely disposes all animation controllers.
  void _disposeControllers() {
    _fadeController?.dispose();
    _fadeController = null;
    _stepFadeController?.dispose();
    _stepFadeController = null;
    _clipMorphController?.dispose();
    _clipMorphController = null;
    _isTransitioning = false;
  }
}
