import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:audyn/src/bloc/player/player_bloc.dart';
import 'package:audyn/src/core/constants/assets.dart';

class NextButton extends StatelessWidget {
  const NextButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        context.read<PlayerBloc>().add(PlayerNext());
      },
      icon: SvgPicture.asset(Assets.nextSvg, width: 40),
      tooltip: 'Next',
    );
  }
}
