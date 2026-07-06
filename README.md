# cloudcosttree — price data

This repo publishes only the AWS price catalog (`data/prices.json`) used by
[CloudCostTree](https://github.com/rulssss/Cost_tree). It's refreshed
periodically from the AWS Price List API and fetched at runtime by the CLI
— no AWS credentials required to consume it.

There is no source code here; the tool itself lives in a separate,
private repository.
