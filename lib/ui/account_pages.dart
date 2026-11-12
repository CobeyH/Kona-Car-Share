part of 'app.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.model});
  final AppModel model;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool create = false;
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  final key = GlobalKey<FormState>();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: 'Kona Share',
    children: [
      const Icon(Icons.electric_car, size: 100, color: ink),
      title(
        context,
        create ? 'Welcome to the house.' : 'Your house. Your Kona.',
      ),
      small('Request a trip, share the car, and settle up fairly.'),
      Form(
        key: key,
        child: Column(
          children: [
            if (create)
              TextFormField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Your name'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Enter your name' : null,
              ),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  v?.contains('@') == true ? null : 'Enter an email address',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: password,
              obscureText: true,
              autofillHints: [
                create ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) =>
                  (v?.length ?? 0) >= 8 ? null : 'Use at least 8 characters',
            ),
          ],
        ),
      ),
      FilledButton(
        onPressed: widget.model.busy
            ? null
            : () async {
                if (!key.currentState!.validate()) return;
                await widget.model.run(
                  () => widget.model.repository.auth(
                    email.text,
                    password.text,
                    create ? name.text : null,
                  ),
                );
              },
        child: Text(
          widget.model.busy
              ? 'Please wait…'
              : create
              ? 'Create account'
              : 'Sign in',
        ),
      ),
      OutlinedButton(
        onPressed: widget.model.busy
            ? null
            : () => widget.model.run(widget.model.repository.googleAuth),
        child: const Text('Continue with Google'),
      ),
      TextButton(
        onPressed: () => setState(() => create = !create),
        child: Text(
          create
              ? 'Already have an account? Sign in'
              : 'New here? Create an account',
        ),
      ),
    ],
  );
}

class JoinPage extends StatefulWidget {
  const JoinPage({super.key, required this.model});
  final AppModel model;
  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final code = TextEditingController(),
      name = TextEditingController(text: 'The Kona house');
  @override
  void dispose() {
    code.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormFrame(
    title: 'Find your house',
    children: [
      title(context, 'One car. One group.'),
      small(
        'An owner can invite you as a borrower or a fellow owner. Your invitation decides your role.',
      ),
      TextField(
        controller: code,
        decoration: const InputDecoration(labelText: 'Invitation code'),
      ),
      FilledButton(
        onPressed: widget.model.busy
            ? null
            : () => widget.model.action('joinGroup', {'code': code.text}),
        child: const Text('Join the group'),
      ),
      const Divider(height: 30),
      title(context, 'Own the Kona?'),
      small('Create a group, then invite your co-owner and roommates.'),
      TextField(
        controller: name,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Group name'),
      ),
      OutlinedButton(
        onPressed: widget.model.busy
            ? null
            : () {
                if (name.text.trim().isNotEmpty) {
                  widget.model.action('createGroup', {
                    'name': name.text.trim(),
                  });
                }
              },
        child: const Text('Create a group as owner'),
      ),
      TextButton(
        onPressed: () => widget.model.repository.signOut(),
        child: const Text('Sign out'),
      ),
    ],
  );
}

Future<String?> _askText(
  BuildContext context,
  String title,
  String hint, {
  bool optional = false,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLength: 500,
        decoration: InputDecoration(labelText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () {
            if (optional || controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  // Keep the controller alive through the dialog's reverse animation.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}
