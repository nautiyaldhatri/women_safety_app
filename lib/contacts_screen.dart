import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  /// Saves contacts locally for offline SMS fallback
  Future<void> _cacheContactsLocally(List<Map<String, dynamic>> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = contacts.map((c) => jsonEncode(c)).toList();
    await prefs.setStringList('cached_emergency_contacts', encoded);
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('emergency_contacts')
            .select()
            .eq('user_id', user.id);

        setState(() {
          _contacts = List<Map<String, dynamic>>.from(response);
        });

        // Cache contacts locally for offline SMS fallback
        await _cacheContactsLocally(_contacts);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addContact() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both name and phone number')),
      );
      return;
    }

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Try inserting with contact_name / contact_phone (or fallback to name/phone)
        try {
          await supabase.from('emergency_contacts').insert({
            'user_id': user.id,
            'contact_name': name,
            'contact_phone': phone,
          });
        } catch (_) {
          await supabase.from('emergency_contacts').insert({
            'user_id': user.id,
            'name': name,
            'phone': phone,
          });
        }

        _nameController.clear();
        _phoneController.clear();
        if (mounted) Navigator.pop(context);

        await _loadContacts(); // Reloads list & updates offline local cache!
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding contact: $e')),
        );
      }
    }
  }

  Future<void> _deleteContact(String id) async {
    try {
      await supabase.from('emergency_contacts').delete().eq('id', id);
      await _loadContacts(); // Reloads list & updates offline local cache!
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting contact: $e')),
        );
      }
    }
  }

  void _showAddContactDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Contact Name',
                hintText: 'e.g. Mummy',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '+917860273911',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _addContact,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: Colors.redAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
          ? const Center(
        child: Text(
          'No emergency contacts added yet.\nTap + to add one.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      )
          : ListView.builder(
        itemCount: _contacts.length,
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          final contactName = contact['contact_name'] ?? contact['name'] ?? 'Unknown';
          final contactPhone = contact['contact_phone'] ?? contact['phone'] ?? '';

          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.redAccent,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(contactName),
              subtitle: Text(contactPhone),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: () => _deleteContact(contact['id'].toString()),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        backgroundColor: Colors.redAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}