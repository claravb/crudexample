import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class Person implements Comparable {
  final int id;
  final String firstName;
  final String lastName;

  const Person({
    required this.id,
    required this.firstName,
    required this.lastName,
  });

  String get fullName => '$firstName $lastName';

  Person.fromRow(
      Map<String, Object?> row) // transform from map to list of person
      : id = row['ID'] as int,
        firstName = row['FIRST_NAME'] as String,
        lastName = row['LAST_NAME'] as String;

  @override
  // chronological
  //int compareTo(covariant Person other) => id.compareTo(other.id); appears zero on top, then 1,2,3,...
  // reverse chronological
  int compareTo(covariant Person other) =>
      other.id.compareTo(id); //appears from last

  @override
  bool operator ==(covariant Person other) => id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Person, id = $id, firstName: $firstName, lastName: $lastName';
}

class PersonDB {
  final String dbName;
  Database? _db;
  List<Person> _persons = [];
  final _streamController = StreamController<List<Person>>.broadcast();

  PersonDB({required this.dbName});

  Future<List<Person>> _fetchPeople() async {
    final db = _db; //make sure that the db has been created before
    if (db == null) {
      return [];
    }
    try {
      final read = await db.query(
        'PEOPLE',
        distinct: true,
        columns: ['ID', 'FIRST_NAME', 'LAST_NAME'],
        orderBy: 'ID',
      );

      // now we need to transform this List<Map<String, Object?>> in a List<Person>>
      final people = read.map((row) => Person.fromRow(row)).toList();
      return people;
    } catch (e) {
      print('Error fetching people = $e');
      return [];
    }
  }

  /// C
  Future<bool> create(String firstName, String lastName) async {
    final db = _db;
    if (db == null) {
      return false;
    }

    try {
      final id = await db.insert('PEOPLE', {
        'FIRST_NAME': firstName,
        'LAST_NAME': lastName,
      });
      final person = Person(id: id, firstName: firstName, lastName: lastName);
      _persons.add(person);
      _streamController.add(_persons);
      return true;
    } catch (e) {
      print('Error in creating person = $e');
      return false;
    }
  }

  Future<bool> delete(Person person) async {
    final db = _db;
    if (db == null) {
      return false;
    }

    try {
      final deletedCount =
          await db.delete('PEOPLE', where: 'ID = ?', whereArgs: [person.id]);
      if (deletedCount == 1) {
        _persons.remove(person);
        _streamController.add(_persons);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('Deletion failed with error $e');
      return false;
    }
  }

  Future<bool> close() async {
    final db = _db;
    if (db == null) {
      return false;
    }
    await db.close();
    return true;
  }

  Future<bool> open() async {
    if (_db != null) {
      return true;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$dbName';

    try {
      final db = await openDatabase(path);
      _db = db;

      // create table
      const create = '''CREATE TABLE ID NOT EXISTS PEOPLE (
      ID INTEGER PRIMARY KEY AUTOINCREMENT,
      FIRST_NAME STRING NOT NULL,
      LAST)NAME STRING NOT NULL
      )''';

      await db.execute(create);

      // read all existing Person objects from de db
      _persons = await _fetchPeople();
      // stream controller is your gateway in containing a stream that is not just allowed to read
      _streamController.add(_persons);
      return true;
    } catch (e) {
      print('Error = $e');
      return false;
    }
  }

  Future<bool> update(Person person) async {
    final db = _db;
    if (db == null) {
      return false;
    }

    try {
      final updateCount = await db.update('PEOPLE',
          {'FIRST_NAME': person.firstName, 'LAST_NAME': person.lastName},
          where: 'ID = ?', whereArgs: [person.id]);
      if (updateCount == 1) {
        _persons.removeWhere((other) => other.id == person.id);
        _persons.add(person);
        _streamController.add(_persons);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      print('Failed to update person, error = $e');
      return false;
    }
  }

  //Stream<List<Person>> all() => _streamController.stream;
  Stream<List<Person>> all() =>
      _streamController.stream.map((persons) => persons..sort());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PersonDB _crudStorage;

  @override
  void initState() {
    _crudStorage = PersonDB(dbName: 'db.sqlite');
    _crudStorage.open(); //not needed to put await i don't remember why
    super.initState();
  }

  @override
  void dispose() {
    _crudStorage.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //test();

    return Scaffold(
      appBar: AppBar(title: const Text('Crud example')),
      body: StreamBuilder(
        stream: _crudStorage.all(),
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.active:
            case ConnectionState.waiting:
              if (snapshot.data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final people = snapshot.data as List<Person>;
              //print(people);
              //return const Text('Ok');
              return Column(
                children: [
                  ComposedWidget(
                    onComposed: (firstName, lastName) async {
                      // print(firstName);
                      // print(lastName);
                      await _crudStorage.create(firstName, lastName);
                    },
                  ),
                  Expanded(
                    child: ListView.builder(
                        itemCount: people.length,
                        itemBuilder: (context, index) {
                          //return const Text('Hi');
                          final person = people[index];
                          return ListTile(
                            onTap: () async {
                              final editedPerson =
                                  await showUpdateDialog(context, person);
                              if (editedPerson != null) {
                                await _crudStorage.update(editedPerson);
                              }
                            },
                            title: Text(person.fullName),
                            subtitle: Text('ID: ${person.id}'),
                            trailing: TextButton(
                                onPressed: () async {
                                  final shouldDelete =
                                      await showDeleteDialog(context);
                                  //print(shouldDelete);
                                  if (shouldDelete) {
                                    await _crudStorage.delete(person);
                                  }
                                },
                                child: const Icon(
                                  Icons.disabled_by_default_rounded,
                                  color: Colors.red,
                                )),
                          );
                        }),
                  ),
                ],
              );
            default:
              return const Center(
                child: CircularProgressIndicator(),
              );
          }
        },
      ),
    );
  }
}

Future<bool> showDeleteDialog(BuildContext context) {
  return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: const Text('Are you sure you want to delete this item?'),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('No')),
            TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: const Text('Delete')),
          ],
        );
      }).then((value) {
    if (value is bool) {
      return value;
    } else {
      return false;
    }
  });
}

final _firstNameController = TextEditingController();
final _lastNameController = TextEditingController();

Future<Person?> showUpdateDialog(BuildContext context, Person person) {
  _firstNameController.text = person.firstName;
  _lastNameController.text = person.lastName;
  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your updated values here:'),
            TextField(
              controller: _firstNameController,
            ),
            TextField(controller: _lastNameController)
          ],
        ),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.of(context).pop(null);
              },
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final editedPerson = Person(
                  id: person.id,
                  firstName: _firstNameController.text,
                  lastName: _lastNameController.text);

              Navigator.of(context).pop(editedPerson);
            },
            child: const Text('Save'),
          )
        ],
      );
    },
  ).then((value) {
    if (value is Person) {
      return value;
    } else {
      return null;
    }
  });
}

// this is a callback definition
typedef OnCompose = void Function(String firstName, String lastName);

class ComposedWidget extends StatefulWidget {
  final OnCompose onComposed;
  const ComposedWidget({super.key, required this.onComposed});

  @override
  State<ComposedWidget> createState() => _ComposedWidgetState();
}

class _ComposedWidgetState extends State<ComposedWidget> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;

  @override
  void initState() {
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    super.initState();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _firstNameController,
          decoration: const InputDecoration(hintText: 'Enter first name'),
        ),
        TextField(
          controller: _lastNameController,
          decoration: const InputDecoration(hintText: 'Enter last name'),
        ),
        TextButton(
          child: const Text(
            'Add to List:',
            style: TextStyle(fontSize: 24),
          ),
          onPressed: () {
            final firstName = _firstNameController.text;
            final lastName = _lastNameController.text;
            widget.onComposed(firstName, lastName);
            _firstNameController.text = '';
            _lastNameController.text = '';
          },
        )
      ],
    );
  }
}

void main() {
  runApp(MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage()));
}
