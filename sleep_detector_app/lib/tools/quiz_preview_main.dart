// 시험 도구: 음성 퀴즈 화면만 바로 띄워 보기 (디자인 확인용, 11/16)
//   flutter build apk --debug -t lib/tools/quiz_preview_main.dart --dart-define=QUIZ_TYPE=repeat|add
import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../screens/quiz_screen.dart';
import '../theme.dart';

void main() {
  const type = String.fromEnvironment('QUIZ_TYPE', defaultValue: 'repeat');
  final quiz = VoiceQuiz(
    quizId: 'preview',
    type: type,
    speak: type == 'add' ? '이십삼 더하기 십사는?' : '따라 말해 주세요. 졸음쉼터에서 잠깐 쉬겠습니다',
    display: type == 'add' ? '23 + 14 = ?' : '졸음쉼터에서\n잠깐 쉬겠습니다',
    listenSec: 30,
  );
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: buildAppTheme(), home: QuizScreen(quiz: quiz, stage: 2, previewGuide: const String.fromEnvironment('GUIDE', defaultValue: '🎤 말씀해 주세요'), previewHeard: type == 'add' ? '삼십칠' : '졸음쉼터에서 잠깐 쉬겠습니다')));
}
