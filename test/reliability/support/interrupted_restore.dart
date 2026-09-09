import 'dart:io';
import 'package:yalla_accounts/core/services/restore_file_journal.dart';

Future<void> main(List<String> args) async {
  final journal = await RestoreFileJournal.begin(args[0]);
  await journal.replace(File(args[1]), args[0]);
  await journal.replace(File(args[3]), args[2]);
  await journal.replace(File(args[3]), '${args[2]}.new');
  stdout.writeln('READY');
  await stdin.first;
}
