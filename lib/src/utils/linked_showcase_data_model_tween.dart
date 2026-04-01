import 'package:flutter/widgets.dart';

import '../models/linked_showcase_data_model.dart';

/// Interpolates between two [LinkedShowcaseDataModel] values.
///
/// Used to smoothly animate the showcase cutout position between steps.
class LinkedShowcaseDataModelTween
    extends Tween<LinkedShowcaseDataModel> {
  LinkedShowcaseDataModelTween({
    required LinkedShowcaseDataModel begin,
    required LinkedShowcaseDataModel end,
  }) : super(begin: begin, end: end);

  @override
  LinkedShowcaseDataModel lerp(double t) => LinkedShowcaseDataModel(
        rect: Rect.lerp(begin!.rect, end!.rect, t)!,
        radius: BorderRadius.lerp(begin!.radius, end!.radius, t),
        overlayPadding:
            EdgeInsets.lerp(begin!.overlayPadding, end!.overlayPadding, t)!,
        isCircle: t < 0.5 ? begin!.isCircle : end!.isCircle,
      );
}

/// Interpolates a list of [LinkedShowcaseDataModel] values element-wise.
List<LinkedShowcaseDataModel> lerpLinkedShowcaseDataList(
  List<LinkedShowcaseDataModel> a,
  List<LinkedShowcaseDataModel> b,
  double t,
) {
  // If lengths differ, snap to target list at the halfway point.
  if (a.length != b.length) return t < 0.5 ? a : b;

  return [
    for (var i = 0; i < a.length; i++)
      LinkedShowcaseDataModelTween(begin: a[i], end: b[i]).lerp(t),
  ];
}
