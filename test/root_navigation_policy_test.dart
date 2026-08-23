import 'package:chat/features/chats/root_navigation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RootNavigationPlan', () {
    test('four or fewer destinations stay direct', () {
      final plan = RootNavigationPlan.forDestinationCount(4);
      expect(plan.hasOverflow, isFalse);
      expect(plan.primaryIndices, <int>[0, 1, 2, 3]);
      expect(plan.overflowIndices, isEmpty);
      expect(plan.bottomItemCount, 4);
      expect(plan.selectedBottomIndex(3), 3);
    });

    test('more than four becomes first three plus More', () {
      final plan = RootNavigationPlan.forDestinationCount(7);
      expect(plan.hasOverflow, isTrue);
      expect(plan.primaryIndices, <int>[0, 1, 2]);
      expect(plan.overflowIndices, <int>[3, 4, 5, 6]);
      expect(plan.bottomItemCount, 4);
      expect(plan.moreBottomIndex, 3);
    });

    test('overflow destinations select the More item', () {
      final plan = RootNavigationPlan.forDestinationCount(6);
      expect(plan.selectedBottomIndex(0), 0);
      expect(plan.selectedBottomIndex(2), 2);
      expect(plan.selectedBottomIndex(3), 3);
      expect(plan.selectedBottomIndex(5), 3);
      expect(plan.destinationForOverflowTap(0), 3);
      expect(plan.destinationForOverflowTap(2), 5);
    });

    test('invalid destination counts and indices fail closed', () {
      expect(
        () => RootNavigationPlan.forDestinationCount(0),
        throwsArgumentError,
      );
      final plan = RootNavigationPlan.forDestinationCount(5);
      expect(() => plan.selectedBottomIndex(5), throwsRangeError);
      expect(() => plan.destinationForPrimaryTap(3), throwsRangeError);
      expect(() => plan.destinationForOverflowTap(2), throwsRangeError);
    });
  });
}
