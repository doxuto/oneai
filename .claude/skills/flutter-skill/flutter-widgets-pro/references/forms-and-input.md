# Forms, focus, and input

Read this for text entry, validation, keyboard handling, and touch. Most form bugs in Flutter are ownership bugs (a controller built in `build`), focus bugs (a shared or undisposed `FocusNode`), or inset bugs (content hidden behind the keyboard).

## `Form` anatomy

```dart
class SignUpForm extends StatefulWidget {
  const SignUpForm({super.key});
  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();               // dismiss the keyboard
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.signUp(_email.text.trim());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Account created')));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            controller: _email,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (String? v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            focusNode: _passwordFocus,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'Password'),
            validator: (String? v) =>
                (v == null || v.length < 8) ? 'At least 8 characters' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Creating…' : 'Create account'),
          ),
        ],
      ),
    );
  }
}
```

`FormState` API: `validate()` (returns `bool`, runs every `validator`), `save()` (runs every `onSaved`), `reset()`. `Form.onChanged` fires on any field change. Since 3.35 `Form` is no longer usable as a sliver — wrap the sliver content, or put the `Form` above the `CustomScrollView`.

## `autovalidateMode`

| Value | Behaviour |
|---|---|
| `disabled` | Validate only on `validate()` — the default |
| `always` | Validate on every build, including the first |
| `onUserInteraction` | Validate a field after the user has interacted with it |
| `onUnfocus` | Validate a field when it loses focus |
| `onUserInteractionIfError` | Re-validate on interaction only once the field already has an error |

`always` shows red errors on a pristine form; that is almost never what is wanted. `onUserInteraction` or `onUserInteractionIfError` is the sensible default. Set it on the `Form`; individual `FormField`s can override.

## `TextFormField` vs `TextField`

`TextFormField` is a `FormField<String>` wrapping a `TextField`. Use it inside a `Form`; use `TextField` for search boxes and other non-validated input. `initialValue` and `controller` are mutually exclusive — passing both asserts. Prefer a controller whenever you need to read or reset the value.

Parameters that matter and are commonly omitted:

| Parameter | Why |
|---|---|
| `keyboardType` | `emailAddress`, `number`, `phone`, `url`, `multiline`, `visiblePassword` |
| `textInputAction` | `next` / `done` / `search` drives the return key |
| `textCapitalization` | `words` for names, `sentences` for prose |
| `autofillHints` | Enables OS password managers and one-time-code autofill |
| `obscureText` + `enableSuggestions: false` + `autocorrect: false` | Passwords |
| `maxLines: null` + `minLines:` | Growing multi-line input |
| `inputFormatters` | Structural constraints (below) |
| `onEditingComplete` vs `onSubmitted` | The former does not unfocus by default when overridden |

Wrap the fields in an `AutofillGroup` so the platform treats them as one credential set, and call `TextInput.finishAutofillContext()` after a successful submit so iOS offers to save the password.

## `TextInputFormatter`

Formatters run on every keystroke, in order, before the value reaches the controller.

```dart
inputFormatters: <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(6),
],
```

`FilteringTextInputFormatter` has `.allow(RegExp)`, `.deny(RegExp)`, the `digitsOnly` static, and a `singleLineFormatter`. `LengthLimitingTextInputFormatter` enforces a maximum. Anything else is a custom `TextInputFormatter` overriding `formatEditUpdate(oldValue, newValue)`.

Do not use a formatter for validation messages — a formatter silently discards input, which reads as a broken keyboard. Use it only for structure (digits, length, a mask) and a `validator` for everything the user must be told about. When a custom formatter rewrites the text, recompute `TextEditingValue.selection` or the caret jumps to the end on every keystroke.

## Focus

- One `FocusNode` per field, created in `initState`/as a `late final` field and disposed in `dispose`. Sharing a node between two fields makes both appear focused.
- `node.requestFocus()` to move focus; `FocusScope.of(context).nextFocus()` / `previousFocus()` to move within a scope; `FocusScope.of(context).unfocus()` to dismiss the keyboard.
- `autofocus: true` on at most one widget per route.
- `FocusScope` defines a traversal group. Wrap a modal or a nested form in `FocusScope` so tab/next stays inside it.
- `FocusTraversalGroup(policy: OrderedTraversalPolicy())` plus `FocusTraversalOrder(order: NumericFocusOrder(n))` when the visual order differs from the widget order.
- `Focus(onKeyEvent: ...)` for keyboard shortcuts on desktop and web; `Shortcuts` + `Actions` for the declarative form.
- A `FocusNode` used only to detect focus changes still needs `addListener`/`removeListener` and disposal.

## Keyboard insets

- `Scaffold.resizeToAvoidBottomInset` defaults to `true`: the body is resized by `MediaQuery.viewInsetsOf(context).bottom`. Set it to `false` only when you position content manually, and then add the inset yourself.
- Inside a scroll view, add `padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom)` to the content — or use `SafeArea(bottom: true, maintainBottomViewPadding: true)`.
- A bottom sheet that contains a field needs `isScrollControlled: true` on `showModalBottomSheet` plus the `viewInsets` padding, or the keyboard covers it.
- `Scrollable.ensureVisible(focusNode.context!)` in a focus listener scrolls a focused field into view when the automatic behaviour is not enough.
- `GestureDetector(onTap: () => FocusScope.of(context).unfocus(), behavior: HitTestBehavior.opaque)` around the body is the standard tap-outside-to-dismiss; `TextField` already handles its own taps.

## Gestures and hit testing

| Widget | Use |
|---|---|
| `InkWell` / `InkResponse` | Anything Material that should ripple. Requires a `Material` ancestor |
| `GestureDetector` | Non-Material gestures, custom drags, or where no visual feedback is wanted |
| `IconButton`, `FilledButton`, `ListTile`, `Card(child: InkWell)` | Prefer a real component over a `GestureDetector` — they bring semantics, focus, ripple and a 48 dp target |
| `Listener` | Raw pointer events; no gesture arena |
| `MouseRegion` | Hover on desktop and web |
| `Dismissible` | Swipe to dismiss; needs a key |

Rules:

- A ripple that does not appear means no `Material` ancestor, or an opaque widget painted between the `InkWell` and the `Material`. Wrap in `Material(type: MaterialType.transparency)` or move the colour onto the `Material`. Since 3.44 `ListTile` reports a debug error for exactly this case.
- `GestureDetector` with a `null` callback does not participate in hit testing. `behavior: HitTestBehavior.opaque` makes an otherwise-transparent area tappable; `translucent` lets widgets beneath receive the event too.
- A child outside its parent's bounds (a `Positioned` with a negative offset, an overflowing `Stack` child) does not receive taps, whatever `clipBehavior` says. Resize the parent.
- Two gesture detectors competing (a horizontal drag inside a vertical `ListView`) resolve in the gesture arena; the more specific recognizer usually wins. Use `RawGestureDetector` with custom `GestureRecognizerFactory` entries only when you must override that.
- `onTapDown`/`onTapUp`/`onTapCancel` for press states; do not simulate a long press with a timer.
- Every tap target is at least 48×48 logical pixels — see `accessibility.md`.

Text fields backed by a provider, debounced search, and form state that must outlive the route belong to `riverpod-pro`; `enterText`/`pumpAndSettle` assertions belong to `flutter-testing-pro`.
