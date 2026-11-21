import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/shared/art/exercise_figures.dart';

const _ids = ['pushup', 'situp', 'jacks', 'squat', 'toes', 'unknown-exercise'];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
  TextDirection dir = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: dir,
      child: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduceMotion),
        child: Center(child: child),
      ),
    ),
  );
}

void main() {
  test('task ids map to their own drawing; unknown ids fall back', () {
    expect(exerciseMoveFor('pushup'), ExerciseMove.pushup);
    expect(exerciseMoveFor('situp'), ExerciseMove.situp);
    expect(exerciseMoveFor('jacks'), ExerciseMove.jacks);
    expect(exerciseMoveFor('squat'), ExerciseMove.squat);
    expect(exerciseMoveFor('toes'), ExerciseMove.toes);
    expect(exerciseMoveFor('jump-rope'), ExerciseMove.generic);
    expect(exerciseMoveFor(''), ExerciseMove.generic);
  });

  group('figures build', () {
    for (final id in _ids) {
      for (final size in [56.0, 96.0]) {
        for (final dir in TextDirection.values) {
          for (final reduce in [false, true]) {
            testWidgets('$id ${size.toInt()}dp ${dir.name} ${reduce ? 'reduce-motion' : 'motion'}', (tester) async {
              await _pump(
                tester,
                Row(mainAxisSize: MainAxisSize.min, children: [
                  ExerciseFigure(key: const Key('still'), taskId: id, size: size),
                  AnimatedExerciseFigure(key: const Key('anim'), taskId: id, size: size, color: const Color(0xFF6C3BEB)),
                ]),
                reduceMotion: reduce,
                dir: dir,
              );
              await tester.pump(const Duration(milliseconds: 700));
              expect(tester.takeException(), isNull);
              expect(tester.getSize(find.byKey(const Key('still'))), Size.square(size));
              expect(tester.getSize(find.byKey(const Key('anim'))), Size.square(size));
              expect(
                find.descendant(of: find.byKey(const Key('anim')), matching: find.byType(RepaintBoundary)),
                findsAtLeastNWidgets(1),
              );
              // Moves only when motion is allowed.
              expect(tester.binding.hasScheduledFrame, !reduce);

              // RTL mirrors the figure so it faces the text.
              final flip = tester.widget<Transform>(
                find.descendant(of: find.byKey(const Key('still')), matching: find.byType(Transform)).first,
              );
              expect(flip.transform.storage[0], dir == TextDirection.rtl ? -1 : 1);
            });
          }
        }
      }
    }
  });

  testWidgets('animated figure stops with reduce-motion and hops on +1', (tester) async {
    Widget figure(int reps) => AnimatedExerciseFigure(taskId: 'jacks', reps: reps);

    await _pump(tester, figure(0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // A rep plays the hop without errors.
    await _pump(tester, figure(1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    // Turning reduce-motion on stops every ticker, even after another rep.
    await _pump(tester, figure(2), reduceMotion: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animate: false shows the still pose (e.g. exercise handed in)', (tester) async {
    await _pump(tester, const AnimatedExerciseFigure(taskId: 'squat', animate: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('painter repaints only when its inputs change', () {
    final a = ExerciseFigurePainter(move: ExerciseMove.pushup, color: const Color(0xFFFF6B6B));
    expect(a.shouldRepaint(ExerciseFigurePainter(move: ExerciseMove.pushup, color: const Color(0xFFFF6B6B))), isFalse);
    expect(a.shouldRepaint(ExerciseFigurePainter(move: ExerciseMove.squat, color: const Color(0xFFFF6B6B))), isTrue);
    expect(a.poseT, ExerciseMove.pushup.stillPose);
  });
}
