import argparse
import os
import pandas as pd


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
        '-o', '--outname', required=True,
        help=(
            'Output name for the filtered file.'
            )
    )
    return parser.parse_args()


def filter_on_frame(df):
    """
    Filter the dataframe to remove all rows except 'INFRAME' ones
    :param df:
    :returns a filtered df:
    """
    try:
        filtered_df = df.loc[df["PROT_FUSION_TYPE"] == "INFRAME"]
        return filtered_df
    except KeyError:
        print("The PROT_FUSION_TYPE column was not found - filtering couldn't run")
        exit(1)


def main():
    args = get_args()
    try:
        input_file = pd.read_csv(args.input_file, sep="\t")
    except FileNotFoundError:
        print("The FusionInspector coding-effect-annotated abridged file was not found - filtering couldn't run")
        exit(1)
    output_df = filter_on_frame(input_file)
    output_df.to_csv(args.outname, sep="\t", index=False)


if __name__ == "__main__":
    main()
