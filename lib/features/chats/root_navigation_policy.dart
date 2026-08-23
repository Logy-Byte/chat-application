class RootNavigationPlan {
  const RootNavigationPlan._({
    required this.destinationCount,
    required this.primaryIndices,
    required this.overflowIndices,
  });

  factory RootNavigationPlan.forDestinationCount(int destinationCount) {
    if (destinationCount < 1) {
      throw ArgumentError.value(
        destinationCount,
        'destinationCount',
        'Root navigation requires at least one destination.',
      );
    }
    if (destinationCount <= 4) {
      return RootNavigationPlan._(
        destinationCount: destinationCount,
        primaryIndices: List<int>.unmodifiable(
          List<int>.generate(destinationCount, (index) => index),
        ),
        overflowIndices: const <int>[],
      );
    }
    return RootNavigationPlan._(
      destinationCount: destinationCount,
      primaryIndices: const <int>[0, 1, 2],
      overflowIndices: List<int>.unmodifiable(
        List<int>.generate(destinationCount - 3, (index) => index + 3),
      ),
    );
  }

  final int destinationCount;
  final List<int> primaryIndices;
  final List<int> overflowIndices;

  bool get hasOverflow => overflowIndices.isNotEmpty;
  int get bottomItemCount => primaryIndices.length + (hasOverflow ? 1 : 0);
  int get moreBottomIndex => hasOverflow ? primaryIndices.length : -1;

  int selectedBottomIndex(int destinationIndex) {
    _validateDestination(destinationIndex);
    if (!hasOverflow) return destinationIndex;
    return destinationIndex < primaryIndices.length
        ? destinationIndex
        : moreBottomIndex;
  }

  int destinationForPrimaryTap(int bottomIndex) {
    if (bottomIndex < 0 || bottomIndex >= primaryIndices.length) {
      throw RangeError.index(bottomIndex, primaryIndices, 'bottomIndex');
    }
    return primaryIndices[bottomIndex];
  }

  int destinationForOverflowTap(int overflowIndex) {
    if (!hasOverflow) {
      throw StateError('Root navigation has no overflow destinations.');
    }
    if (overflowIndex < 0 || overflowIndex >= overflowIndices.length) {
      throw RangeError.index(
        overflowIndex,
        overflowIndices,
        'overflowIndex',
      );
    }
    return overflowIndices[overflowIndex];
  }

  void _validateDestination(int destinationIndex) {
    if (destinationIndex < 0 || destinationIndex >= destinationCount) {
      throw RangeError.range(
        destinationIndex,
        0,
        destinationCount - 1,
        'destinationIndex',
      );
    }
  }
}
