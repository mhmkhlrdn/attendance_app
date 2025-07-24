class SchoolClass {
  final String id;
  final String className;
  final int year;
  final String grade;
  final List<String> students;

  SchoolClass({
    required this.id,
    required this.className,
    required this.year,
    required this.grade,
    required this.students,
  });

  Map<String, dynamic> toMap() {
    return {
      'class_name': className,
      'year': year,
      'grade': grade,
      'students': students,
    };
  }

  factory SchoolClass.fromMap(String id, Map<String, dynamic> map) {
    return SchoolClass(
      id: id,
      className: map['class_name'],
      year: map['year'],
      grade: map['grade'],
      students: List<String>.from(map['students'] ?? []),
    );
  }
}