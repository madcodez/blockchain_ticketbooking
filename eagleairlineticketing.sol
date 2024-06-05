// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract EagleAirlinesTicketing{
    address  public airline; // airline account
   

    struct Flight { //create a flight details for booking
        string flightNumber;
        string seatCategory;
        uint256 flightDatetime;
        string status; 
    }

    struct Customer {
        address customerAddress;
        Flight[] flightDetails;
        uint256 totalAmountPaid;
        mapping(string => string) confirmationId;
        mapping(string => bool) isTicketCancelled;
       
    }

    mapping(address => bool) public isAirline;
    mapping(address => Flight[]) public customerBookings;
    mapping(address => Customer) public customers;
    mapping(address => bool) public isCustomer;
    mapping(string => uint256) public ticketPrice;

    event Debug(string message, uint256 value);
   
    uint256 private confirmationIdCounter = 1;

    Flight[] public availableFlights;

    mapping(string => Flight) public flights;
   // Percentage penalty predefined by the airlines 
    uint256 public penaltyPercentage = 20;

    constructor(){
        availableFlights.push(Flight("EAG123", "Economy", block.timestamp +  3 hours,"on-time"));
        availableFlights.push(Flight("BUS456", "Business", block.timestamp + 6 hours,"on-time"));
        availableFlights.push(Flight("EMR136", "Business", block.timestamp + 7 hours,"on-time"));
    }

    modifier onlyAirline() {
        require(isAirline[msg.sender], "Only airline can call this function");
        _;
    }

    modifier onlyCustomer() {
    
        require(isCustomer[msg.sender], "Only customers can call this function");
        _;
    }

    function getTicketDetails() external view returns (Flight[] memory) {
      return availableFlights;
    }
    //you should be registered customer 
    function registerCustomer() external {
        require(!isCustomer[msg.sender], "Customer is already registered");
        isCustomer[msg.sender] = true;
    
    }
    //you should be registered airline user 
    function registerAirline() external {
        require(!isAirline[msg.sender], "Customer is already registered");
        isAirline[msg.sender] = true;
        airline = msg.sender;
    
    }
    //Only customer can book and the make the payment for the ticket
    function bookFlightAndPay(
        string memory _flightNumber,
        string memory _seatCategory,
        uint256 _flightDatetime
    ) external payable onlyCustomer{
        require(msg.value > 1 ether, "Payment amount must be greater than 0");

        Flight storage flight = flights[_flightNumber];
         
     
        flight.flightNumber = _flightNumber;
        flight.seatCategory = _seatCategory;
        flight.flightDatetime = _flightDatetime;
        flight.status = "on-time";

        Customer storage customer = customers[msg.sender];
        customer.customerAddress=msg.sender;
        customerBookings[msg.sender].push(flight);
        ticketPrice[_flightNumber] = msg.value;
        customer.totalAmountPaid += msg.value;
        customer.isTicketCancelled[_flightNumber] = false;
        customer.confirmationId[_flightNumber] = generateConfirmationId();
        payable(airline).transfer(msg.value);

    } 

    function getBookedFlight(string memory _flightNumber) internal view returns(Flight memory){
        
        
          for (uint256 i = 0; i < customerBookings[msg.sender].length; i++) {
            if (keccak256(abi.encodePacked(customerBookings[msg.sender][i].flightNumber)) == keccak256(abi.encodePacked(_flightNumber))) {
                return customerBookings[msg.sender][i];
            }
        }
        revert("Flight not found");
           
    }
    // Only Customer should call this function to get the booking details
    function getBookingDetails(string memory _flightNumber) external view onlyCustomer returns(Flight memory, string memory) {
        Flight memory flightdetail = getBookedFlight(_flightNumber);
        Customer storage customer = customers[msg.sender];
        return(flightdetail,customer.confirmationId[_flightNumber]);
    }

   

    function cancelBookingByCustomer(string memory _flightNumber) public payable onlyCustomer{

        Customer storage customer = customers[msg.sender];
        Flight memory flightforcancel  = getBookedFlight(_flightNumber);
        //Checking ticket is already cancelled by customert cancelled 
        require(!customer.isTicketCancelled[_flightNumber], "Booking is already cancelled");
        //Checking timestamp is not with in cancellation time stamp 
        require(block.timestamp < flightforcancel.flightDatetime - (2 hours), "Cancellation window has passed");
        // Check if the provided flight number is valid
        require(bytes(flightforcancel.flightNumber).length > 0, "No flight found for cancellation");  
        //Calcutating the refund for the cancelled tickets
        uint256 refundAmount = calculateRefundAmount(ticketPrice[_flightNumber]);
        //Calculating the penatly amount for cancellation which is paid to the airline
        
        uint256 penaltyAmount = ticketPrice[_flightNumber] - refundAmount;
          


         bool success;
         success = payable(msg.sender).send(refundAmount);
         require(!success, "Transfer to customer failed");
          //  bool success;
         success = payable(airline).send(penaltyAmount);
         require(!success, "Transfer to airline failed");
        
        customer.isTicketCancelled[_flightNumber] = true;

        customer.totalAmountPaid -= refundAmount;


    }

    function cancelFlightByAirline(string memory _flightNumber) external payable onlyAirline{
        Flight storage flight = flights[_flightNumber];

         // Check if the provided flight number is valid
        require(bytes(flight.flightNumber).length > 0, "Invalid flight number");

        flight.status = "cancelled";

        bool success;
        success= payable(msg.sender).send(ticketPrice[_flightNumber]);
        require(!success, "Transfer to customer failed");

    }

     function updateFlightStatus(string memory _flightNumber, string memory _status) external onlyAirline {
        Flight storage flight = flights[_flightNumber];

        // Check if the provided flight number is valid
        require(bytes(flight.flightNumber).length > 0, "Invalid flight number");


        // Check if the current time is within 24 hours of the flight start time
        require(block.timestamp < flight.flightDatetime - 1 days, "Flight status can only be updated within 24 hours of the flight start time");


        flight.status = _status;
     }  


    function claimRefund(string memory _flightNumber) external onlyCustomer {
        Customer storage customer = customers[msg.sender];
        Flight storage flight = flights[_flightNumber];

        require(bytes(flight.flightNumber).length > 0, "Invalid flight number");
        require(block.timestamp > flight.flightDatetime + 1 days, "Claim can only be made 24 hours after the flight departure time");

        uint256 refundAmount;
        bool success;
        if (block.timestamp > flight.flightDatetime + 2 days && keccak256(bytes(flight.status)) == keccak256(bytes("cancelled"))) {
            // Airline cancellation case
            refundAmount = ticketPrice[_flightNumber];
        } else {
            

            if (block.timestamp > flight.flightDatetime && keccak256(bytes(flight.status)) == keccak256(bytes("delayed"))) {
                // Delayed flight case
                refundAmount = calculateRefundAmount(ticketPrice[_flightNumber]);
                uint256 penalty = ticketPrice[_flightNumber] - refundAmount;

                // Transfer penalty to the airline
                
                success= payable(msg.sender).send(penalty);
                require(!success, "Transfer to airline failed");
            } else {
                // Flight status is not changed by airline
                refundAmount = ticketPrice[_flightNumber];
            }
        }

        // Refund money to the customer
        
        success= payable(msg.sender).send(refundAmount);
        require(!success, "Transfer to customer failed");

        // Mark the ticket as cancelled
        customer.isTicketCancelled[_flightNumber] = true;

       
    }  


    function calculateRefundAmount(uint256 totalAmount) internal view returns (uint256) {
        uint256 penaltyAmount = (totalAmount * penaltyPercentage) / 100;
        return totalAmount - penaltyAmount;
    }
  

    function generateConfirmationId() internal returns (string memory){
        
        string memory confirmationId = string(abi.encodePacked("EATM-", uintToString(confirmationIdCounter)));
        confirmationIdCounter++;
        return confirmationId;
        
    } 

    function uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len;
        for (uint256 i = v; i > 0; i /= 10) len++;
        bytes memory bstr = new bytes(len);
        for (uint256 i = len; i > 0; i--) {
            bstr[i - 1] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(bstr);
    }  
}