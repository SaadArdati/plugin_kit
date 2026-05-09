/// Mock data used by the Flutter editor shell and its UI plugins.
///
/// Keeps the big string blobs and canned response lists out of the plugin
/// and shell files so those stay focused on behavior.
library;

import 'package:code_editor/code_editor.dart';

/// A fresh SQL document shown in the initial SQL tab.
TextDocument initialSqlDocument() => TextDocument(
  filename: 'query.sql',
  content: _sqlContent,
  languageId: 'sql',
);

/// A fresh Dart document shown in the initial Dart tab.
TextDocument initialDartDocument() => TextDocument(
  filename: 'main.dart',
  content: _dartContent,
  languageId: 'dart',
);

/// Fake compiler/runner output streamed by the Runner plugin's console panel.
const runnerFakeOutput = <String>[
  'Compiling main.dart...',
  'Resolving dependencies...',
  'Building application...',
  '✓ Build completed in 1.2s',
  '',
  'Running main.dart...',
  'Hello, World!',
  'Fetching data from API...',
  '✓ Loaded 42 records',
  'Processing records...',
  '✓ All tasks completed successfully.',
];

/// Canned AI responses streamed out character-by-character by the AI assist
/// panel. Cycled per user message.
const aiAssistCannedResponses = <String>[
  'This function iterates through the list and applies the transformation. '
      'Consider using `map()` for a more idiomatic approach. It creates a new list '
      'without mutating the original. Also, the null check on line 12 can be '
      'simplified with a null-aware operator: `value?.toString() ?? ""`. '
      'This pattern is common in Dart and makes the intent clearer.',
  'The error is likely caused by a missing `await` on the async call at line 8. '
      'Without it, the function returns a `Future<String>` instead of `String`, '
      'which causes the type mismatch downstream. Adding `await` and marking '
      'the enclosing function as `async` should resolve it.',
  'I\'d suggest extracting this logic into a separate class. The current function '
      'handles validation, transformation, and persistence: three distinct '
      'responsibilities. A `UserValidator`, a `UserMapper`, and the existing '
      'repository would be cleaner and easier to test independently.',
  'The widget rebuilds every frame because `setState` is called inside the '
      'stream listener without checking if the value actually changed. Wrap it '
      'in a comparison: `if (_currentValue != newValue) setState(() => _currentValue = newValue);`. '
      'Alternatively, consider using `ValueListenableBuilder` to scope the rebuild.',
];

/// A single mock file entry shown in the Git changes panel.
class GitMockFile {
  final String path;
  final String status; // 'M' modified, 'A' added.
  final int additions;
  final int deletions;
  const GitMockFile(this.path, this.status, this.additions, this.deletions);
}

/// The uncommitted changes listed in the Git panel before the user hits
/// "Commit".
const gitMockChanges = <GitMockFile>[
  GitMockFile('lib/main.dart', 'M', 12, 3),
  GitMockFile('lib/models/user.dart', 'M', 45, 8),
  GitMockFile('test/user_test.dart', 'A', 28, 0),
];

/// A single rendered line in the terminal panel. Used for both the prompts
/// the user typed and the canned command responses.
class TerminalLine {
  final String text;
  final bool isPrompt;
  final bool isError;
  final bool isSuccess;
  const TerminalLine(
    this.text, {
    this.isPrompt = false,
    this.isError = false,
    this.isSuccess = false,
  });
}

/// Output for the `ls` command.
const terminalLsOutput = <TerminalLine>[
  TerminalLine('lib/'),
  TerminalLine('  main.dart'),
  TerminalLine('  models/'),
  TerminalLine('    user.dart'),
  TerminalLine('test/'),
  TerminalLine('  user_test.dart'),
  TerminalLine('pubspec.yaml'),
  TerminalLine('README.md'),
];

/// Output for the `help` command.
const terminalHelpOutput = <TerminalLine>[
  TerminalLine('Available commands:'),
  TerminalLine(
    '  dart run         Run the application (triggers Runner plugin)',
  ),
  TerminalLine('  dart analyze     Analyze for issues'),
  TerminalLine('  dart test        Run tests'),
  TerminalLine('  ls               List files'),
  TerminalLine('  pwd              Print working directory'),
  TerminalLine('  git status       Show git status'),
  TerminalLine('  git log          Show commit log'),
  TerminalLine('  clear            Clear terminal'),
  TerminalLine('  help             Show this help'),
];

/// Output for `dart analyze`.
const terminalDartAnalyzeOutput = <TerminalLine>[
  TerminalLine('Analyzing lib...'),
  TerminalLine('  info - main.dart:3:1 - TODO comment found'),
  TerminalLine('  info - main.dart:4:1 - TODO comment found'),
  TerminalLine('  warning - user.dart:12:5 - Unused variable'),
  TerminalLine('3 issues found.'),
];

/// Output for `dart test`.
const terminalDartTestOutput = <TerminalLine>[
  TerminalLine('Running tests...'),
  TerminalLine('  +1: user creation test', isSuccess: true),
  TerminalLine('  +2: user validation test', isSuccess: true),
  TerminalLine('  +3: user serialization test', isSuccess: true),
  TerminalLine('All tests passed!', isSuccess: true),
];

/// Output for `git status`.
const terminalGitStatusOutput = <TerminalLine>[
  TerminalLine('On branch main'),
  TerminalLine('Changes not staged for commit:'),
  TerminalLine('  modified:  lib/main.dart'),
  TerminalLine('  modified:  lib/models/user.dart'),
  TerminalLine(''),
  TerminalLine('Untracked files:'),
  TerminalLine('  test/user_test.dart'),
];

/// Output for `git log`.
const terminalGitLogOutput = <TerminalLine>[
  TerminalLine('a1b2c3d feat: add user model'),
  TerminalLine('e4f5g6h fix: resolve null check'),
  TerminalLine('i7j8k9l init: project scaffold'),
];

/// The terminal prompt under `/home/user/my_project`.
const terminalPwdOutput = TerminalLine('/home/user/my_project');

// Sample inputs used by the bin/* CLI examples.

/// Markdown sample used by `bin/01_hello_extension.dart`.
const sampleMarkdown = '''
# Welcome to plugin_kit

This is a [guide](https://example.com) for building plugins.

## Getting Started

```dart
void main() {}
```

### Advanced Topics

See [the docs](https://docs.example.com) for more.
''';

/// Messy SQL with mixed case and runs of inner whitespace. Used by
/// `bin/03_formatter_pipeline.dart` and `bin/05_workspace_sessions.dart`.
const messySql =
    'select   name, email   \n'
    'from   users   \n'
    'where  active = true   \n'
    'order by   name   ';

/// Poorly-indented Dart source used by `bin/03_formatter_pipeline.dart`.
const messyDart =
    'void main() {\n'
    'print("hi");\n'
    'if (true) {\n'
    'print("nested");\n'
    '}\n'
    '}\n';

/// Dart source with TODO comments and one over-long line. Used by
/// `bin/04_diagnostics.dart`.
const dartSourceWithTodos = '''
import 'package:flutter/material.dart';

// TODO: Refactor this class to use the new widget API instead of the deprecated one from the legacy codebase
class MyWidget extends StatelessWidget {
  // TODO: add proper documentation
  @override
  Widget build(BuildContext context) {
    return Container(); // This line is fine
  }
}
''';

/// Single-line SQL statement used by `bin/06_extension_competition.dart`.
const sqlOneLiner =
    'select id, name from users where active = true order by name limit 10';

/// Messy SQL with a different column set than [messySql]. Used by
/// `bin/05_workspace_sessions.dart` to demonstrate session isolation.
const messySqlAccounts =
    'select   id, name   \nfrom   accounts   \nwhere  active = true   ';

/// Tiny Dart class with trailing whitespace on each line. Used by
/// `bin/05_workspace_sessions.dart` as the Dart-side format target.
const messyDartService = 'class UserService {\n  final String name;   \n}   ';

/// 85-character Dart line used by `bin/08_editor_settings.dart` to exercise
/// the configurable-max-line-length linter.
const dartLine85 =
    'final result = computeValue(parameterOne, parameterTwo, parameterThree, extra);  ';

const _sqlContent = '''-- Users table queries
-- TODO: add pagination support

select
  u.id,
  u.name,
  u.email,
  u.created_at,
  count(o.id) as order_count
from users u
left join orders o on o.user_id = u.id
where u.active = true
  and u.created_at > '2024-01-01'
group by u.id, u.name, u.email, u.created_at
having count(o.id) > 0
order by u.created_at desc
limit 50;

-- Recent orders with product details
select
  o.id as order_id,
  o.total_amount,
  o.status,
  p.name as product_name,
  p.price,
  oi.quantity
from orders o
inner join order_items oi on oi.order_id = o.id
inner join products p on p.id = oi.product_id
where o.status in ('pending', 'processing')
order by o.created_at desc;

-- Update inactive users
update users
set active = false,
    updated_at = current_timestamp
where last_login < '2023-06-01'
  and active = true;

-- Insert new product category
insert into categories (name, slug, description)
values ('Electronics', 'electronics', 'Gadgets and devices');
''';

const _dartContent = '''import 'package:flutter/material.dart';

// TODO: extract theme configuration into a separate file
// TODO: add responsive breakpoints for tablet/desktop layouts

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const TaskListScreen(),
    );
  }
}

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final List<Task> _tasks = [
    Task(title: 'Design new landing page', priority: Priority.high, completed: false),
    Task(title: 'Fix login bug on Safari', priority: Priority.critical, completed: false),
    Task(title: 'Write unit tests for auth module', priority: Priority.medium, completed: true),
    Task(title: 'Update dependencies', priority: Priority.low, completed: false),
    Task(title: 'Review pull request #142', priority: Priority.medium, completed: false),
  ];

  // TODO: implement proper state management with a provider or bloc instead of this inline approach that is getting increasingly hard to maintain across the widget tree
  int get _completedCount => _tasks.where((t) => t.completed).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '\$_completedCount / \${_tasks.length} done',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          return TaskTile(
            task: task,
            onToggle: () {
              setState(() {
                task.completed = !task.completed;
              });
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addTask() {
    // TODO: show a dialog to create a new task
    setState(() {
      _tasks.add(Task(
        title: 'New Task \${_tasks.length + 1}',
        priority: Priority.medium,
        completed: false,
      ));
    });
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.onToggle});

  final Task task;
  final VoidCallback onToggle;

  Color _priorityColor(Priority priority) {
    return switch (priority) {
      Priority.critical => Colors.red,
      Priority.high => Colors.orange,
      Priority.medium => Colors.blue,
      Priority.low => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Checkbox(value: task.completed, onChanged: (_) => onToggle()),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        trailing: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _priorityColor(task.priority),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

enum Priority { critical, high, medium, low }

class Task {
  final String title;
  final Priority priority;
  bool completed;

  Task({required this.title, required this.priority, required this.completed});
}
''';
