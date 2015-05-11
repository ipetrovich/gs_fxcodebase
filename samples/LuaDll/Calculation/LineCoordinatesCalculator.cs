using System;
using System.Collections.Generic;
using System.Text;

namespace Calculation
{
    public class LineCoordinatesCalculator
    {
        public static double GetLineStartDate()
        {
            DateTime time = (DateTime.UtcNow - new TimeSpan(2, 0, 0));
            // NOTE:  - 5.0 / 24.0 to convert UTC time to EST time.
            // Use proper time conversion here!
            return time.ToOADate() - 5.0 / 24.0;
        }

        public static double GetLineEndDate()
        {
            // NOTE:  - 5.0 / 24.0 to convert UTC time to EST time.
            // Use proper time conversion here!
            return DateTime.UtcNow.ToOADate() - 5.0 / 24.0;
        }

        public static double GetLineStartLevel(double level)
        {
            return level - level * 0.01;
        }

        public static double GetLineEndLevel(double level)
        {
            return level + level * 0.01;
        }
    }
}
