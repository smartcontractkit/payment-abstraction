const parse = require("lcov-parse");
const ignore = require("./coverage.ignore.json");

parse("./lcov.info", function(err, data) {
  data.forEach(({ file, branches, functions, lines }) => {
    if (file.startsWith("script") || file.startsWith("test")) return;

    console.log(`Analyzing coverage for ${file}`);

    for (const ignoreFile of ignore) {
      if (file.includes(ignoreFile)) {
        console.log(`Ignoring coverage for ${file}`);
        return;
      }
    }

    analyze(file, "Branch", branches.hit, branches.found, branches.details);
    analyze(
      file,
      "Function",
      functions.hit,
      functions.found,
      functions.details,
    );
    analyze(file, "Line", lines.hit, lines.found, lines.details);
  });
});

const analyze = (file, section, numHits, numFound, details) => {
  if (numHits < numFound) {
    const percentage = (100.0 * numHits) / numFound;
    throw new Error(
      `${section} coverage for ${file} is at ${percentage}% \n Missed hits:\n ${JSON.stringify(
        details.filter((branch) => branch.taken === 0 || branch.hit === 0),
      )}`,
    );
  }
};
