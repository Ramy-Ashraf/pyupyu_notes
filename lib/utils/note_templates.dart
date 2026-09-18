/// Built-in note templates used by "New from template".
class NoteTemplate {
  const NoteTemplate({required this.name, required this.body});

  final String name;
  final String body;
}

const List<NoteTemplate> noteTemplates = [
  NoteTemplate(
    name: 'Meeting notes',
    body: 'Meeting — title & date\n\n'
        'Attendees: \nGoal: \n\n'
        '☐ Review last actions\n'
        '☐ New topics\n'
        '☐ Decisions\n\n'
        'Notes:\n- \n\n'
        'Actions:\n☐ @name task + due\n',
  ),
  NoteTemplate(
    name: 'Todo list',
    body: 'Todo — today\n\n'
        '☐ Most important task\n'
        '☐ Second task\n'
        '☐ Quick win\n\n'
        'Done:\n☒ \n',
  ),
  NoteTemplate(
    name: 'Project plan',
    body: 'Project — name\n\n'
        '#goal Define the outcome\n\n'
        '1. Milestone one\n'
        '2. Milestone two\n'
        '3. Launch\n\n'
        '| Task | Owner | Due |\n'
        '| ---- | ----- | --- |\n'
        '|      |       |     |\n',
  ),
  NoteTemplate(
    name: 'Blank table',
    body: 'Table\n\n'
        '| A | B | C |\n'
        '| --- | --- | --- |\n'
        '|  |  |  |\n'
        '|  |  |  |\n',
  ),
];
