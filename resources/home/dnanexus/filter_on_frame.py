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


def filter_on_frame(df):
    """
    Filter the dataframe to remove all rows except 'INFRAME' ones
    :param df:
    :returns a filtered df:
    """
    filtered_df = df.loc[df["PROT_FUSION_TYPE"] == "INFRAME"]
    return filtered_df


def main():
    args = get_args()
    input_file = pd.read_csv(args.input_file, sep="\t")
    output_df = filter_on_frame(input_file)
    outname = args.out_dir + "/" + args.output_prefix + ".FusionInspector.fusions.abridged.tsv.coding_effect.filtered"
    output_df.to_csv(outname, sep="\t", index=False)


if __name__ == "__main__":
    main()
