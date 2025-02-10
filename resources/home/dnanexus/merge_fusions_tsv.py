import argparse
import os
import pandas as pd

def parse_args():
    """
	Allow arguments from the command line to be given.
    Array of .FusionInspector.fusions.abridged.tsv.coding_effect files
	are needed.

    Returns:
        args: Variable that you can extract relevant
        arguements inputs needed
    """

    parser = argparse.ArgumentParser()

    parser.add_argument(
        '-a', '--array',
        nargs='+',
        required=True,
        help='an array of coding_effect files'
        )
	
    parser.add_argument(
        '-o', '--output_directory',
        help='path to output directory',
        required=True
        )

    args = parser.parse_args()

    return args

def merge_files(args):
	""""
	Merges all the fusions and drops any duplicate rows

	Args:
		args: array of files taken from command lines

	Returns:
		dfs: dictionary containing merged + deduplicated pandas dataframe
	"""

	dfs = {}

	for file in args.array:
		if file.endswith(".coding_effect"):
			df = pd.read_csv(file, sep='\t')
			file_basename = os.path.basename(file).split('_')[0]
			if file_basename in dfs:
				dfs[file_basename] = pd.concat([dfs[file_basename], df]).drop_duplicates(subset=[
					'#FusionName', 'JunctionReadCount', 'SpanningFragCount', 'est_J', 'est_S', 'LeftGene',
					'LeftLocalBreakpoint', 'LeftBreakpoint', 'RightGene', 'RightLocalBreakpoint', 'RightBreakpoint',
					'SpliceType', 'LargeAnchorSupport', 'NumCounterFusionLeft', 'NumCounterFusionRight', 'FAR_left', 'FAR_right']
					).reset_index(drop=True)
				dfs[file_basename] =  dfs[file_basename].sort_values(by=['JunctionReadCount', 'SpanningFragCount'], ascending=False)
			else:
				dfs[file_basename] = df

	return dfs

def main():
	args = parse_args()

	merged_files = merge_files(args)

	for basename, merged_df in merged_files.items():
		output_path = os.path.join(args.output_directory, f"{basename}_FusionInspector.fusions.abridged.merged.tsv")
		merged_df.to_csv(output_path, index=False, sep='\t')
		print(f"Merged file saved to {output_path}")


if __name__ == "__main__":

    main()

