class CalorieTargets {
  const CalorieTargets({
    required this.trainingDayCalories,
    required this.restDayCalories,
  });

  final int trainingDayCalories;
  final int restDayCalories;

  Map<String, dynamic> toJson() => {
    'trainingDayCalories': trainingDayCalories,
    'restDayCalories': restDayCalories,
  };

  factory CalorieTargets.fromJson(Map<String, dynamic> json) => CalorieTargets(
    trainingDayCalories: (json['trainingDayCalories'] as num).toInt(),
    restDayCalories: (json['restDayCalories'] as num).toInt(),
  );
}
