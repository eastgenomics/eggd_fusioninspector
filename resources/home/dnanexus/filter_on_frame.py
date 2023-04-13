import argparse
import os


def get_args():
    parser = argparse.ArgumentParser(
        description="Filter a FusionInspector coding-effect-annotated abridged file, to retain only \
            those results which are in-frame."
        )
    parser.add_argument(
        '-i', '--input_file', required=True,
        help=(
            'Path to the FusionInspector coding-effect-annotated abridged file, which will be filtered.'
            )
        ),
    parser.add_argument(
        '-o', '--output_prefix', required=True,
        help=(
            'Output name prefix for the filtered file.'
            )
    ),
    parser.add_argument(
        '--out_dir', required=False, default=os.getcwd(),
        help="Path to the output directory. Uses current workdir if not specified."
    )
    return parser.parse_args()


def main():
    args = get_args()


if __name__ == "__main__":
    main()
