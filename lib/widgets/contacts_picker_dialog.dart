import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/member_model.dart';
import '../providers/contacts_provider.dart';
import '../utils/constants.dart';

/// A reusable dialog that lists saved contacts with checkboxes for multi-select.
/// [excludeEmails] — emails already in the current group (won't be shown).
class ContactsPickerDialog extends ConsumerStatefulWidget {
  final List<String> excludeEmails;
  final void Function(List<MemberModel> selected) onSelected;

  const ContactsPickerDialog({
    super.key,
    required this.onSelected,
    this.excludeEmails = const [],
  });

  @override
  ConsumerState<ContactsPickerDialog> createState() =>
      _ContactsPickerDialogState();
}

class _ContactsPickerDialogState extends ConsumerState<ContactsPickerDialog> {
  final Set<String> _selectedKeys = {}; // email or member id
  String _search = '';

  String _key(MemberModel m) => m.email.isNotEmpty ? m.email : m.id;

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(userContactsProvider);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.contacts, color: Color(0xFF00897B)),
          SizedBox(width: 8),
          Text('Choose from Contacts'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: contactsAsync.when(
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error loading contacts: $e'),
          data: (allContacts) {
            final available = allContacts
                .where((c) => !widget.excludeEmails.contains(c.email))
                .where((c) =>
                    _search.isEmpty ||
                    c.name.toLowerCase().contains(_search.toLowerCase()) ||
                    c.email.toLowerCase().contains(_search.toLowerCase()))
                .toList();

            if (allContacts.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_search, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No contacts yet.\nAdd members to a group to save them as contacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search contacts…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No matching contacts',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: available.length,
                      itemBuilder: (_, i) {
                        final contact = available[i];
                        final key = _key(contact);
                        final isSelected = _selectedKeys.contains(key);
                        final color =
                            AppConstants.colorFromHex(contact.colorHex);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedKeys.add(key);
                              } else {
                                _selectedKeys.remove(key);
                              }
                            });
                          },
                          secondary: CircleAvatar(
                            backgroundColor: color,
                            radius: 18,
                            child: Text(
                              contact.name.isNotEmpty
                                  ? contact.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(contact.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: contact.email.isNotEmpty
                              ? Text(contact.email,
                                  style: const TextStyle(fontSize: 12))
                              : null,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.trailing,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: Text(_selectedKeys.isEmpty
              ? 'Add Selected'
              : 'Add (${_selectedKeys.length})'),
          onPressed: _selectedKeys.isEmpty
              ? null
              : () {
                  final allContacts =
                      ref.read(userContactsProvider).valueOrNull ?? [];
                  final selected = allContacts
                      .where((c) => _selectedKeys.contains(_key(c)))
                      .toList();
                  widget.onSelected(selected);
                  Navigator.of(context).pop();
                },
        ),
      ],
    );
  }
}

