import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  List<Map<String, dynamic>> contacts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final data = await Supabase.instance.client
        .from('emergency_contacts')
        .select()
        .eq('user_id', userId as Object);

    setState(() {
      contacts = List<Map<String, dynamic>>.from(data);
      isLoading = false;
    });
  }

  Future<void> _addContact() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (nameController.text.trim().isEmpty || phoneController.text.trim().isEmpty) {
      // Added: give feedback instead of silently doing nothing.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both name and phone number')),
      );
      return;
    }

    await Supabase.instance.client.from('emergency_contacts').insert({
      'user_id': userId,
      'contact_name': nameController.text.trim(),
      'contact_phone': phoneController.text.trim(),
    });

    nameController.clear();
    phoneController.clear();
    _loadContacts();
  }

  Future<void> _deleteContact(String id) async {
    await Supabase.instance.client.from('emergency_contacts').delete().eq('id', id);
    _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Contacts')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Contact Name'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number (e.g. +919999999999)'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addContact,
              child: const Text('Add Contact'),
            ),
            const SizedBox(height: 20),
            const Divider(),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : contacts.isEmpty
                  ? const Center(child: Text('No emergency contacts yet'))
                  : ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return ListTile(
                    title: Text(contact['contact_name']),
                    subtitle: Text(contact['contact_phone']),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteContact(contact['id']),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}